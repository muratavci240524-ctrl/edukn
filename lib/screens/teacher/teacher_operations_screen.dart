import 'package:flutter/material.dart';
import '../school/profile_settings_screen.dart';
import 'teacher_lessons_screen.dart';
import 'teacher_student_list_screen.dart';

class TeacherOperationsScreen extends StatefulWidget {
  final String institutionId;

  const TeacherOperationsScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherOperationsScreen> createState() => _TeacherOperationsScreenState();
}

class _TeacherOperationsScreenState extends State<TeacherOperationsScreen> {
  String? _expandedCategory;
  String _selectedCategory = 'Tümü';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öğretmen İşlemleri',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Size Tanımlı Modüller',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.account_circle_outlined, color: Colors.white),
            tooltip: 'Profilim',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const ProfileSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildCategorySelector(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(16),
                  children: [
                    // DERS PROGRAMIM KISMI - Tümü ekranında en üstte görünecek özel buton (Kullanıcının isteği)
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Derslerim')
                      Card(
                        elevation: 2,
                        margin: EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => TeacherLessonsScreen(institutionId: widget.institutionId),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 28),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Derslerim / Programım',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Sadece kendi ders programınızı görüntüleyin',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                    
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Öğrenci Yönetimi')
                      _buildExpandableCategory(
                        categoryId: 'ogrenciler',
                        title: 'Öğrenci Yönetimi',
                        icon: Icons.people_alt,
                        color: Colors.green,
                        children: [
                          _buildModuleItem(
                            Icons.list_alt,
                            'Tanımlı Öğrencilerim',
                            Colors.green,
                            'Sadece size tanımlı olan öğrencileri listeleyin',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => TeacherStudentListScreen(institutionId: widget.institutionId),
                                ),
                              );
                            },
                          ),
                          _buildModuleItem(Icons.fact_check_outlined, 'Yoklama İşlemleri', Colors.green, 'Dersinize girdiğiniz sınıfların yoklamasını alın'),
                          _buildModuleItem(Icons.folder_special, 'Öğrenci Portfolyoları', Colors.green, 'Öğrencilerinizin durumunu inceleyin'),
                        ],
                      ),
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Öğrenci Yönetimi')
                      SizedBox(height: 12),

                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Eğitim')
                      _buildExpandableCategory(
                        categoryId: 'egitim',
                        title: 'Eğitim İşlemleri',
                        icon: Icons.school,
                        color: Colors.orange,
                        children: [
                          _buildModuleItem(Icons.assignment, 'Ödev İşlemleri', Colors.orange, 'Ödev verin ve kontrol edin'),
                          _buildModuleItem(Icons.play_lesson, 'Ders İşleyiş Planı', Colors.orange, 'Günlük ve yıllık planlarınızı yönetin'),
                          _buildModuleItem(Icons.task, 'Etüt İşlemleri', Colors.orange, 'Tanımlı etütleri yönetin'),
                        ],
                      ),
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Eğitim')
                      SizedBox(height: 12),

                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Ölçme')
                      _buildExpandableCategory(
                        categoryId: 'olcme',
                        title: 'Ölçme Değerlendirme',
                        icon: Icons.bar_chart,
                        color: Colors.red,
                        children: [
                          _buildModuleItem(Icons.assessment, 'Sınav İşlemleri', Colors.red, 'Deneme ve Sınav notları girin'),
                          _buildModuleItem(Icons.analytics_outlined, 'Sınav Raporları', Colors.red, 'Detaylı analizleri inceleyin'),
                        ],
                      ),
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Ölçme')
                      SizedBox(height: 12),
                      
                    if (_selectedCategory == 'Tümü' || _selectedCategory == 'Görev')
                      _buildExpandableCategory(
                        categoryId: 'gorev',
                        title: 'Görevlendirme ve İzin',
                        icon: Icons.assignment_ind,
                        color: Colors.brown,
                        children: [
                          _buildModuleItem(Icons.security, 'Nöbetlerim', Colors.brown, 'Nöbet bilgilerinizi görün'),
                          _buildModuleItem(Icons.time_to_leave, 'İzin İşlemleri', Colors.brown, 'İzin talep edin ve geçmişi görün'),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded, 'id': 'Tümü'},
      {'label': 'Derslerim', 'icon': Icons.calendar_month, 'id': 'Derslerim'},
      {'label': 'Öğrenci Yönetimi', 'icon': Icons.people_alt, 'id': 'Ogrenciler'},
      {'label': 'Eğitim', 'icon': Icons.school, 'id': 'egitim'},
      {'label': 'Ölçme', 'icon': Icons.bar_chart, 'id': 'olcme'},
      {'label': 'Görev', 'icon': Icons.assignment_ind, 'id': 'gorev'},
    ];

    return Container(
      width: double.infinity,
      height: 120,
      child: Center(
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
                      if (_selectedCategory != 'Tümü') {
                        _expandedCategory = cat['id'] as String;
                      } else {
                        _expandedCategory = null;
                      }
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
                              ? Colors.indigo.withOpacity(0.3)
                              : Colors.black.withOpacity(0.05),
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
    );
  }

  Widget _buildExpandableCategory({
    required String categoryId,
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedCategory == categoryId || _selectedCategory == title;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategory = null;
                } else {
                  _expandedCategory = categoryId;
                }
              });
            },
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${children.length} İşlem Modülü',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: children,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModuleItem(IconData icon, String title, Color color, String subtitle, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ?? () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title Sayfası (Öğretmene Özel)')));
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    )
                  ]
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
