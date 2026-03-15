import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SchoolTypeStatsScreen extends StatefulWidget {
  const SchoolTypeStatsScreen({Key? key}) : super(key: key);

  @override
  _SchoolTypeStatsScreenState createState() => _SchoolTypeStatsScreenState();
}

class _SchoolTypeStatsScreenState extends State<SchoolTypeStatsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  String? _institutionId;
  List<Map<String, dynamic>> _schoolTypes = [];
  bool _isLoading = true;
  // Yetkilendirme için
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
    _loadData();
  }

  // Kullanıcı yetkilendirme bilgilerini yükle
  Future<void> _loadUserPermissions() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      // Kullanıcı verilerini çek
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userData = userQuery.docs.first.data();
      }
    } catch (e) {
      print('Kullanıcı yetkileri yüklenirken hata: $e');
    }
  }

  // Belirli bir okul türüne erişim var mı?
  bool _hasSchoolTypeAccess(String schoolTypeId) {
    // Admin kullanıcısı (userData yok) - Tüm okul türlerine erişim var
    if (userData == null) return true;

    final schoolTypes = userData!['schoolTypes'] as List<dynamic>? ?? [];
    return schoolTypes.contains(schoolTypeId);
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      final schoolTypesSnapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: instId)
          .get();

      if (schoolTypesSnapshot.docs.isNotEmpty) {
        _schoolTypes = schoolTypesSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        // Okul Türleri sayfasındaki sıralama ile aynı olması için sırala
        const List<String> sortOrder = [
          'Anaokulu',
          'İlkokul',
          'Ortaokul',
          'Lise',
          'Kurs',
          'Diğer',
        ];

        _schoolTypes.sort((a, b) {
          final String? aType = a['schoolType'];
          final String? bType = b['schoolType'];

          final int aIndex = aType != null
              ? sortOrder.indexOf(aType)
              : sortOrder.length;
          final int bIndex = bType != null
              ? sortOrder.indexOf(bType)
              : sortOrder.length;

          int typeComparison = aIndex.compareTo(bIndex);
          if (typeComparison != 0) return typeComparison;

          // Aynı türdekileri oluşturulma tarihine göre (yeni olan üste) sırala
          final aTime = a['createdAt'] as Timestamp?;
          final bTime = b['createdAt'] as Timestamp?;
          return (bTime ?? Timestamp(0, 0)).compareTo(aTime ?? Timestamp(0, 0));
        });

        // Sadece erişim yetkisi olan okul türlerini filtrele
        if (userData != null) {
          _schoolTypes = _schoolTypes
              .where((st) => _hasSchoolTypeAccess(st['id']))
              .toList();
        }

        _tabController = TabController(
          length: _schoolTypes.length + 1, // +1 for "Genel" tab
          vsync: this,
        );
      }

      setState(() {
        _institutionId = instId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veri yüklenirken hata oluştu: $e')),
      );
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Okul Türü İstatistikleri',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: _isLoading || _schoolTypes.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dashboard, size: 18),
                        SizedBox(width: 6),
                        Text('Genel'),
                      ],
                    ),
                  ),
                  ..._schoolTypes.map((st) {
                    return Tab(text: st['schoolTypeName'] ?? 'İsimsiz');
                  }).toList(),
                ],
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_schoolTypes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'İstatistik gösterecek okul türü bulunamadı.',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildGeneralStatsPage(), // Genel Tab
        ..._schoolTypes.map((schoolType) {
          return _buildStatsPageForSchoolType(schoolType);
        }).toList(),
      ],
    );
  }

  // Genel İstatistikler - Tüm Okul Türlerinin Toplamı
  Widget _buildGeneralStatsPage() {
    int totalCapacity = 0;
    int totalStudents = 0;
    int totalTeachers = 0;
    int totalClasses = 0;

    for (var schoolType in _schoolTypes) {
      totalCapacity += (schoolType['capacity'] ?? 0) as int;
      totalStudents += (schoolType['studentCount'] ?? 0) as int;
      totalTeachers += (schoolType['teacherCount'] ?? 0) as int;
      totalClasses += (schoolType['classCount'] ?? 0) as int;
    }

    final double overallOccupancy = totalCapacity > 0
        ? (totalStudents / totalCapacity) * 100
        : 0.0;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.dashboard, color: Colors.indigo, size: 28),
            SizedBox(width: 12),
            Text(
              'Genel İstatistikler',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'Tüm okul türlerinin toplam istatistikleri',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        SizedBox(height: 24),

        // Genel Doluluk Oranı
        _buildOverallOccupancyCard(
          totalStudents,
          totalCapacity,
          overallOccupancy,
        ),
        SizedBox(height: 16),

        // Sınıf ve Personel Sayıları
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Sınıf Sayısı',
                value: totalClasses.toString(),
                icon: Icons.class_,
                color: Colors.green,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Personel Sayısı',
                value: totalTeachers.toString(),
                icon: Icons.people,
                color: Colors.blue,
                hasDetail: true,
                onTap: () =>
                    _showPersonnelDetail(null), // Genel personel detayı
              ),
            ),
          ],
        ),
        SizedBox(height: 24),

        // Veli İstatistikleri Bölümü
        Row(
          children: [
            Icon(Icons.family_restroom, color: Colors.indigo, size: 24),
            SizedBox(width: 8),
            Text(
              'Veli İstatistikleri',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        _buildParentStatsSection(null), // Genel veli istatistikleri
        SizedBox(height: 24),

        // Okul Türleri Özet Listesi
        Text(
          'Okul Türlerine Göre Dağılım',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),

        ..._schoolTypes.map((schoolType) {
          final int capacity = schoolType['capacity'] ?? 0;
          final int students = schoolType['studentCount'] ?? 0;
          final double occupancy = capacity > 0
              ? (students / capacity) * 100
              : 0.0;

          return Card(
            margin: EdgeInsets.only(bottom: 8),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        schoolType['schoolTypeName'] ?? 'İsimsiz',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          schoolType['schoolType'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Öğrenci: $students${capacity > 0 ? ' / $capacity' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (capacity > 0) ...[
                              SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: occupancy / 100,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.indigo,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (capacity > 0) ...[
                        SizedBox(width: 16),
                        Text(
                          '${occupancy.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildStatsPageForSchoolType(Map<String, dynamic> schoolType) {
    final List<dynamic> grades = schoolType['activeGrades'] ?? [];
    final List<dynamic> displayGrades =
        grades.isEmpty ? ['Genel'] : grades; // Veri yoksa da 0'lı satır göster
    final String schoolTypeId = schoolType['id'];
    final int? capacity = schoolType['capacity'];
    final int totalStudents = schoolType['studentCount'] ?? 0;
    final int totalTeachers = schoolType['teacherCount'] ?? 0;
    final int totalClasses = schoolType['classCount'] ?? 0;

    final double overallOccupancy = capacity != null && capacity > 0
        ? (totalStudents / capacity) * 100
        : 0.0;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // Header
        Text(
          'Sınıf Düzeyi Doluluk Oranları',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),

        // Tabloyu kart içine al (header + satırlar)
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderRow(),
              const Divider(height: 1, thickness: 1),
              ...displayGrades.map((grade) {
                return _buildGradeStatsRow(
                  gradeName: grade.toString(),
                  schoolTypeId: schoolTypeId,
                );
              }).toList(),
            ],
          ),
        ),

        if (grades.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: Text(
                'Bu okul türü için sınıf düzeyi tanımlanmamış.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),

        Divider(height: 32),

        // Genel Doluluk Oranı
        _buildOverallOccupancyCard(
          totalStudents,
          capacity ?? 0,
          overallOccupancy,
        ),
        SizedBox(height: 16),

        // Sınıf ve Personel Sayıları
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Sınıf Sayısı',
                value: totalClasses.toString(),
                icon: Icons.class_,
                color: Colors.green,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Personel Sayısı',
                value: totalTeachers.toString(),
                icon: Icons.people,
                color: Colors.blue,
                hasDetail: true,
                onTap: () => _showPersonnelDetail(schoolTypeId),
              ),
            ),
          ],
        ),
        SizedBox(height: 24),

        // Veli İstatistikleri Bölümü
        Row(
          children: [
            Icon(Icons.family_restroom, color: Colors.indigo, size: 24),
            SizedBox(width: 8),
            Text(
              'Veli İstatistikleri',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        _buildParentStatsSection(schoolTypeId),
      ],
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Sınıf Düzeyi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Kapasite',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Mevcut',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Boş',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Doluluk',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeStatsRow({
    required String gradeName,
    required String schoolTypeId,
  }) {
    // TODO: Bu veriler Firestore'dan çekilmeli.
    // Örnek: Sınıf kapasitesi ve o sınıftaki öğrenci sayısı
    final int capacity = 0; // Varsayılan
    final int currentStudents = 0; // Varsayılan
    final int available = capacity - currentStudents;
    final double occupancy = capacity > 0
        ? (currentStudents / capacity) * 100
        : 0.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              gradeName,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              capacity.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blue),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              currentStudents.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              available.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: occupancy / 100,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '${occupancy.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallOccupancyCard(
    int totalStudents,
    int totalCapacity,
    double overallOccupancy,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Genel Doluluk Oranı',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        totalStudents.toString(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Mevcut Öğrenci',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(height: 40, width: 1, color: Colors.grey.shade300),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        totalCapacity.toString(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Toplam Kapasite',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: overallOccupancy / 100,
                      minHeight: 16,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  '${overallOccupancy.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Stat Card Widget
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool hasDetail = false,
    VoidCallback? onTap,
  }) {
    Widget card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 28),
                if (hasDetail)
                  Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
              ],
            ),
            SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );

    if (hasDetail && onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }

    return card;
  }

  // Personel Detay Dialogu
  void _showPersonnelDetail(String? schoolTypeId) {
    // TODO: Firestore'dan personel verilerini çek
    // Şimdilik örnek veriler
    Map<String, int> personnelData = {
      'İdareci': 5,
      'Öğretmen': 45,
      'Diğer Personel': 12,
    };

    // Öğretmen branşları (örnek)
    Map<String, int> teacherBranches = {
      'Matematik': 8,
      'Türkçe': 7,
      'İngilizce': 6,
      'Fen Bilgisi': 8,
      'Sosyal Bilgiler': 6,
      'Beden Eğitimi': 4,
      'Müzik': 3,
      'Resim': 3,
    };

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.people, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personel Detayı',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            schoolTypeId == null
                                ? 'Tüm Okul Türleri'
                                : 'Okul Türü Bazlı',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Personel Kategorileri
                      Text(
                        'Personel Kategorileri',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      SizedBox(height: 12),

                      ...personnelData.entries.map((entry) {
                        IconData icon;
                        Color color;

                        switch (entry.key) {
                          case 'İdareci':
                            icon = Icons.admin_panel_settings;
                            color = Colors.orange;
                            break;
                          case 'Öğretmen':
                            icon = Icons.school;
                            color = Colors.blue;
                            break;
                          default:
                            icon = Icons.badge;
                            color = Colors.green;
                        }

                        return Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(icon, color: color, size: 24),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  entry.value.toString(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),

                      SizedBox(height: 24),
                      Divider(),
                      SizedBox(height: 16),

                      // Öğretmen Branşları
                      Row(
                        children: [
                          Icon(Icons.category, color: Colors.indigo, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Öğretmen Branşları',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),

                      ...teacherBranches.entries.map((entry) {
                        return InkWell(
                          onTap: () => _showTeacherList(entry.key, entry.value),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 8),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.indigo,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      entry.key,
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        entry.value.toString(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Öğretmen Listesi Dialogu (Branşa tıklanınca)
  void _showTeacherList(String branch, int count) {
    // TODO: Firestore'dan ilgili branştaki öğretmenleri çek
    // Şimdilik örnek veriler
    List<Map<String, String>> teachers = List.generate(
      count,
      (index) => {
        'teacherName': '${branch} Öğretmeni ${index + 1}',
        'email': 'ogretmen${index + 1}@example.com',
      },
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.school, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$branch Öğretmenleri',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$count öğretmen',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.all(16),
                  itemCount: teachers.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final teacher = teachers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Icon(Icons.person, color: Colors.blue),
                      ),
                      title: Text(
                        teacher['teacherName']!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        teacher['email']!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      trailing: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          branch,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Veli İstatistikleri Widget'ı
  Widget _buildParentStatsSection(String? schoolTypeId) {
    // TODO: Firestore'dan veli verilerini çek
    // Şimdilik örnek veriler

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Adres İstatistikleri Kartı
        _buildParentStatsCard(
          title: 'Adres İstatistikleri',
          subtitle: 'Öğrencilerin yaşadığı il ve ilçeler',
          icon: Icons.location_on,
          color: Colors.green,
          onTap: () => _showAddressStats(schoolTypeId),
        ),
        SizedBox(height: 12),

        // Meslek İstatistikleri Kartı
        _buildParentStatsCard(
          title: 'Meslek İstatistikleri',
          subtitle: 'Velilerin meslek dağılımı',
          icon: Icons.work,
          color: Colors.purple,
          onTap: () => _showProfessionStats(schoolTypeId),
        ),
      ],
    );
  }

  Widget _buildParentStatsCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // Adres İstatistikleri Dialogu
  void _showAddressStats(String? schoolTypeId) {
    // TODO: Firestore'dan adres verilerini çek
    // Şimdilik örnek veriler
    Map<String, Map<String, int>> addressStats = {
      'Ankara': {
        'Etimesgut': 45,
        'Çankaya': 32,
        'Keçiören': 28,
        'Yenimahalle': 21,
      },
      'İstanbul': {'Kadıköy': 15, 'Beşiktaş': 8},
    };

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adres İstatistikleri',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'İl ve ilçe bazlı öğrenci dağılımı',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: addressStats.entries.map((cityEntry) {
                      int cityTotal = cityEntry.value.values.reduce(
                        (a, b) => a + b,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // İl Başlığı
                          Container(
                            padding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            margin: EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  cityEntry.key,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$cityTotal öğrenci',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // İlçeler
                          ...cityEntry.value.entries.map((districtEntry) {
                            double percentage =
                                (districtEntry.value / cityTotal) * 100;

                            return InkWell(
                              onTap: () => _showParentList(
                                '${cityEntry.key} - ${districtEntry.key}',
                                districtEntry.value,
                              ),
                              child: Container(
                                margin: EdgeInsets.only(bottom: 8),
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            districtEntry.key,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            '${districtEntry.value} öğrenci',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '%${percentage.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),

                          SizedBox(height: 20),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Meslek İstatistikleri Dialogu
  void _showProfessionStats(String? schoolTypeId) {
    // TODO: Firestore'dan meslek verilerini çek
    // Şimdilik örnek veriler
    Map<String, int> professionStats = {
      'Öğretmen': 45,
      'Mühendis': 38,
      'Doktor': 32,
      'İşçi': 28,
      'Memur': 25,
      'Esnaf': 22,
      'Serbest Meslek': 18,
      'Diğer': 15,
    };

    int total = professionStats.values.reduce((a, b) => a + b);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.work, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meslek İstatistikleri',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Velilerin meslek dağılımı',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: professionStats.entries.map((entry) {
                      double percentage = (entry.value / total) * 100;

                      return InkWell(
                        onTap: () => _showParentList(entry.key, entry.value),
                        child: Container(
                          margin: EdgeInsets.only(bottom: 10),
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple.shade100),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${entry.value}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: percentage / 100,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.purple,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '%${percentage.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Veli Listesi Dialogu (İstatistiğe tıklanınca)
  void _showParentList(String category, int count) {
    // TODO: Firestore'dan ilgili velileri çek
    // Şimdilik örnek veriler
    List<Map<String, String>> parents = List.generate(
      count > 10 ? 10 : count, // İlk 10 veli
      (index) => {
        'parentName': 'Veli ${index + 1}',
        'studentName': 'Öğrenci ${index + 1}',
      },
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_alt, color: Colors.indigo, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$count veli',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.all(16),
                  itemCount: parents.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final parent = parents[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        parent['parentName']!,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '(${parent['studentName']})',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (count > 10)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    '...ve ${count - 10} veli daha',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
