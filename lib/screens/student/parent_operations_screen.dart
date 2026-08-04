import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_lessons_screen.dart';
import 'student_homework_stats_screen.dart';
import 'student_attendance_stats_screen.dart';
import 'student_etut_stats_screen.dart';
import 'student_exam_stats_screen.dart';
import '../school/guidance/saved_study_programs_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../school/assessment/assessment_reports_screen.dart';


class ParentOperationsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;

  const ParentOperationsScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
  }) : super(key: key);

  @override
  State<ParentOperationsScreen> createState() => _ParentOperationsScreenState();
}

class _ParentOperationsScreenState extends State<ParentOperationsScreen> {
  String _studentId = '';
  String _schoolTypeId = '';
  String _schoolTypeName = '';
  String _classId = '';
  String _className = '';
  String _classLevel = '';
  Map<String, dynamic>? _studentData;
  String _selectedCategory = 'Tümü';

  @override
  void initState() {
    super.initState();
    _loadStudentSchoolType();
  }

  @override
  void didUpdateWidget(ParentOperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.studentId != oldWidget.studentId) {
      _loadStudentSchoolType();
    }
  }

  Future<void> _loadStudentSchoolType() async {
    final stId = widget.studentId;
    if (stId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('students').doc(stId).get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          String classLevel = data['classLevel']?.toString() ?? '';

          // classLevel yoksa sınıf doc'undan al
          final classId = data['classId']?.toString() ?? '';
          if (classLevel.isEmpty && classId.isNotEmpty) {
            try {
              final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
              if (classDoc.exists) {
                classLevel = classDoc.data()?['classLevel']?.toString() ?? '';
              }
            } catch (_) {}
          }

          setState(() {
            _studentId = stId;
            _schoolTypeId = data['schoolTypeId']?.toString() ?? '';
            _schoolTypeName = data['schoolTypeName']?.toString() ?? 'Okul';
            _classId = classId;
            _className = data['className']?.toString() ?? '';
            _classLevel = classLevel;
            _studentData = {...data, 'id': stId};
          });
        }
      } catch (_) {}
    }
  }

  void _openPortfolioTab(int tabIndex) {
    if (_studentData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öğrenci bilgisi yüklenemedi.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PortfolioDetailView(
          student: _studentData!,
          institutionId: widget.institutionId,
          filteredStudents: [_studentData!],
          schoolSettings: const {},
          initialTab: tabIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 24,
                    vertical: isMobile ? 24 : 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategorySelector(),
                      const SizedBox(height: 24),
                      _buildGridSections(isMobile),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded, 'id': 'Tümü'},
      {'label': 'Eğitim İşlemleri', 'icon': Icons.school_rounded, 'id': 'Eğitim'},
      {'label': 'Portfolyo', 'icon': Icons.folder_special_rounded, 'id': 'Portfolyo'},
    ];

    return Container(
      width: double.infinity,
      height: 120,
      child: Center(
        child: ScrollConfiguration(
          behavior: _MouseDraggableScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat['label'] as String;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? Colors.indigo.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected ? Colors.indigo : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected ? Colors.white : Colors.indigo.shade400,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              cat['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSections(bool isMobile) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 1400 ? 1400.0 : screenWidth;
    final availableWidth = contentWidth - (isMobile ? 32 : 48);

    final isFiltered = _selectedCategory != 'Tümü';
    double cardWidth;
    if (isFiltered) {
      cardWidth = availableWidth;
    } else if (availableWidth > 700) {
      cardWidth = (availableWidth - 24) / 2;
    } else {
      cardWidth = availableWidth;
    }

    // Eğitim İşlemleri items
    final educationItems = <Map<String, dynamic>>[
      {
        'title': 'Ders Programı',
        'onTap': () {
          if (_schoolTypeId.isEmpty || _classId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Öğrenci sınıf bilgisi bulunamadı.')),
            );
            return;
          }
          Navigator.push(context, MaterialPageRoute(
            builder: (ctx) => StudentLessonsScreen(
              institutionId: widget.institutionId,
              schoolTypeId: _schoolTypeId,
              schoolTypeName: _schoolTypeName,
              studentId: _studentId,
              classId: _classId,
              className: _className,
            ),
          ));
        },
      },
      {
        'title': 'Ödev İstatistiklerim',
        'onTap': () {
          if (_classId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Öğrenci sınıf bilgisi bulunamadı.')),
            );
            return;
          }
          Navigator.push(context, MaterialPageRoute(
            builder: (ctx) => StudentHomeworkStatsScreen(
              institutionId: widget.institutionId,
              studentId: _studentId,
              classId: _classId,
            ),
          ));
        },
      },
      {
        'title': 'Yoklama İstatistiklerim',
        'onTap': () {
          if (_classId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Öğrenci sınıf bilgisi bulunamadı.')),
            );
            return;
          }
          Navigator.push(context, MaterialPageRoute(
            builder: (ctx) => StudentAttendanceStatsScreen(
              institutionId: widget.institutionId,
              studentId: _studentId,
              classId: _classId,
              studentName: '${(_studentData?['name'] ?? '').toString().trim()} ${(_studentData?['surname'] ?? '').toString().trim()}'.trim(),
            ),
          ));
        },
      },
      {
        'title': 'Etüt İstatistiklerim',
        'onTap': () => Navigator.push(context, MaterialPageRoute(
          builder: (ctx) => StudentEtutStatsScreen(
            institutionId: widget.institutionId,
            studentId: _studentId,
          ),
        )),
      },
      {
        'title': 'Notlarım & Sınavlar',
        'onTap': () => Navigator.push(context, MaterialPageRoute(
          builder: (ctx) => StudentExamStatsScreen(
            institutionId: widget.institutionId,
            studentId: _studentId,
            classId: _classId,
            classLevel: _classLevel,
            studentName: '${(_studentData?['name'] ?? '').toString().trim()} ${(_studentData?['surname'] ?? '').toString().trim()}'.trim(),
            schoolNumber: (_studentData?['schoolNumber'] ?? _studentData?['studentNumber'] ?? _studentData?['no'] ?? '').toString().trim(),
          ),
        )),
      },
      {
        'title': 'Ders Çalışma Programı',
        'onTap': () => Navigator.push(context, MaterialPageRoute(
          builder: (ctx) => SavedStudyProgramsScreen(
            institutionId: widget.institutionId,
            schoolTypeId: _schoolTypeId,
            isTeacher: false,
          ),
        )),
      },
    ];

    // Portfolyo items — portfolio_screen.dart tab sırası
    final portfolioItems = <Map<String, dynamic>>[
      {'title': 'Genel Bilgiler', 'onTap': () => _openPortfolioTab(0)},
      {'title': 'Deneme Sınavları', 'onTap': () => _openPortfolioTab(1)},
      {'title': 'Yazılı Sınavlar', 'onTap': () => _openPortfolioTab(2)},
      {'title': 'Ödevler', 'onTap': () => _openPortfolioTab(3)},
      {'title': 'Devamsızlık', 'onTap': () => _openPortfolioTab(4)},
      {'title': 'Eylem Planları', 'onTap': () => _openPortfolioTab(5)},
      {'title': 'Etütler', 'onTap': () => _openPortfolioTab(6)},
      {'title': 'Kitaplar', 'onTap': () => _openPortfolioTab(7)},
      {'title': 'Görüşmeler', 'onTap': () => _openPortfolioTab(8)},
      {'title': 'Talepler', 'onTap': () => _openPortfolioTab(9)},
      {'title': 'Gelişim Raporu', 'onTap': () => _openPortfolioTab(10)},
      {'title': 'Mentör Çalışmaları', 'onTap': () => _openPortfolioTab(11)},
      {'title': 'Rehberlik Testleri', 'onTap': () => _openPortfolioTab(12)},
      {'title': 'Etkinlik Raporları', 'onTap': () => _openPortfolioTab(13)},
    ];

    final allModules = [
      _ModuleCardWidget(
        title: 'EĞİTİM İŞLEMLERİ',
        badge: 'Eğitim',
        icon: Icons.school_rounded,
        color: Colors.orange,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Eğitim İşlemleri',
        showAllItems: isFiltered && _selectedCategory == 'Eğitim İşlemleri',
        items: educationItems,
        onTap: () => setState(() => _selectedCategory = 'Eğitim İşlemleri'),
      ),
      _ModuleCardWidget(
        title: 'PORTFOLYOM',
        badge: 'Portfolyo',
        icon: Icons.folder_special_rounded,
        color: Colors.indigo,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Portfolyo',
        showAllItems: isFiltered && _selectedCategory == 'Portfolyo',
        items: portfolioItems,
        onTap: () => setState(() => _selectedCategory = 'Portfolyo'),
      ),
    ];

    final filteredModules = (_selectedCategory == 'Tümü'
        ? allModules
        : allModules.where((m) => m.category == _selectedCategory).toList());

    return Wrap(
      key: ValueKey('grid_${_selectedCategory}_$isMobile'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules.toList(),
    );
  }
}

class _MouseDraggableScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _ModuleCardWidget extends StatefulWidget {
  final String title;
  final String badge;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  final double cardWidth;
  final bool isMobile;
  final String? buttonLabel;
  final String category;
  final bool showAllItems;

  const _ModuleCardWidget({
    Key? key,
    required this.title,
    required this.badge,
    required this.icon,
    required this.color,
    required this.items,
    required this.onTap,
    required this.cardWidth,
    required this.isMobile,
    this.buttonLabel,
    required this.category,
    this.showAllItems = false,
  }) : super(key: key);

  @override
  State<_ModuleCardWidget> createState() => _ModuleCardWidgetState();
}

class _ModuleCardWidgetState extends State<_ModuleCardWidget> {
  bool isCardHovered = false;
  int? hoveredItemIndex;

  @override
  Widget build(BuildContext context) {
    final displayedItems = widget.showAllItems ? widget.items : widget.items.take(3).toList();
    final remainingCount = widget.items.length - displayedItems.length;
    final String label = remainingCount > 0
        ? '+$remainingCount işlem daha görüntüle'
        : (widget.buttonLabel ?? 'GÖRÜNTÜLE');

    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: widget.cardWidth,
        height: (widget.isMobile || widget.showAllItems) ? null : 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isCardHovered || widget.showAllItems ? 0.08 : 0.03),
              blurRadius: isCardHovered || widget.showAllItems ? 30 : 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isCardHovered || widget.showAllItems
                ? widget.color.withValues(alpha: 0.3)
                : Colors.indigo.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(widget.isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 28),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: widget.isMobile ? 18 : 22,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                final isHovered = hoveredItemIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => hoveredItemIndex = index),
                    onExit: (_) => setState(() => hoveredItemIndex = null),
                    child: InkWell(
                      onTap: item['onTap'] as VoidCallback,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isHovered ? widget.color : Colors.blueGrey.shade200,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                style: TextStyle(
                                  color: isHovered ? widget.color : Colors.blueGrey.shade600,
                                  fontSize: 14,
                                  fontWeight: isHovered ? FontWeight.w900 : FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isHovered ? widget.color : Colors.blueGrey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!widget.isMobile && !widget.showAllItems) const Spacer(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCardHovered ? widget.color : const Color(0xFFF1F5F9),
                  foregroundColor: isCardHovered ? Colors.white : Colors.blueGrey.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
