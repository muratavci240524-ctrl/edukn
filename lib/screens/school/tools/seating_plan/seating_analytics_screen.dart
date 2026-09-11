import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import '../../../../models/class_model.dart';
import '../../../../services/seating_analytics_service.dart';
import '../../../../widgets/edukn_app_bar.dart';

class SeatingAnalyticsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String? initialClassId;

  const SeatingAnalyticsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialClassId,
  }) : super(key: key);

  @override
  State<SeatingAnalyticsScreen> createState() => _SeatingAnalyticsScreenState();
}

class _SeatingAnalyticsScreenState extends State<SeatingAnalyticsScreen> {
  List<ClassModel> _classes = [];
  String? _selectedClassId;
  String? _selectedClassName;

  ClassSeatingAnalyticsReport? _report;
  bool _isLoadingClasses = true;
  bool _isLoadingReport = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.initialClassId;
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs.map((d) => ClassModel.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => a.className.compareTo(b.className));

      if (mounted) {
        setState(() {
          _classes = list;
          _isLoadingClasses = false;
          if (_selectedClassId == null && list.isNotEmpty) {
            _selectedClassId = list.first.id;
            _selectedClassName = list.first.className;
          } else if (_selectedClassId != null) {
            final match = list.where((c) => c.id == _selectedClassId).toList();
            if (match.isNotEmpty) _selectedClassName = match.first.className;
          }
        });

        if (_selectedClassId != null) {
          _loadAnalyticsReport();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _loadAnalyticsReport() async {
    if (_selectedClassId == null) return;
    setState(() => _isLoadingReport = true);

    try {
      final service = SeatingAnalyticsService();
      final report = await service.generateReportForClass(
        institutionId: widget.institutionId,
        classId: _selectedClassId!,
        className: _selectedClassName ?? '',
      );

      if (mounted) {
        setState(() {
          _report = report;
          _isLoadingReport = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _exportExcel() async {
    if (_report == null || _report!.studentAnalytics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak veri bulunamadı!')),
      );
      return;
    }

    try {
      final service = SeatingAnalyticsService();
      final bytes = service.exportToExcel(_report!);

      if (bytes != null) {
        final fileName = 'Oturma_Analitik_Raporu_${_report!.className}_${DateFormat('ddMMyyyy').format(DateTime.now())}';
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: Uint8List.fromList(bytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Excel raporu başarıyla indirildi!'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel dışa aktarma hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: 'Oturma Planı Analitik',
        subtitle: widget.schoolTypeName,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF1E293B)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'excel') {
                _exportExcel();
              } else if (val == 'refresh') {
                _loadAnalyticsReport();
              }
            },
            itemBuilder: (ctx) => [
              if (_report != null && _report!.studentAnalytics.isNotEmpty)
                PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.table_chart_rounded, size: 18, color: Color(0xFF2E7D32)),
                      ),
                      const SizedBox(width: 10),
                      Text('Excel İndir (.xlsx)', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C6BC0).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF5C6BC0)),
                    ),
                    const SizedBox(width: 10),
                    Text('Raporu Yenile', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filter & Selection Card
                  _buildFilterCard(isMobile),
                  const SizedBox(height: 16),

                  if (_isLoadingReport)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_report == null || _report!.totalPlansAnalyzed == 0)
                    _buildEmptyState()
                  else ...[
                    // Overview Stats
                    _buildOverviewStats(isMobile),
                    const SizedBox(height: 16),

                    // Classroom Heatmap Section
                    _buildHeatmapCard(isMobile),
                    const SizedBox(height: 16),

                    // Student Detail Matrix Table
                    _buildStudentAnalyticsSection(isMobile),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFilterCard(bool isMobile) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedClassId,
                    decoration: InputDecoration(
                      labelText: 'Analiz Edilecek Şube',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.className))).toList(),
                    onChanged: (val) {
                      if (val == null || val == _selectedClassId) return;
                      setState(() {
                        _selectedClassId = val;
                        final match = _classes.where((c) => c.id == val).toList();
                        _selectedClassName = match.isNotEmpty ? match.first.className : '';
                      });
                      _loadAnalyticsReport();
                    },
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loadAnalyticsReport,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Raporu Yenile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedClassId,
                      decoration: InputDecoration(
                        labelText: 'Analiz Edilecek Şube',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0)),
                      ),
                      items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.className))).toList(),
                      onChanged: (val) {
                        if (val == null || val == _selectedClassId) return;
                        setState(() {
                          _selectedClassId = val;
                          final match = _classes.where((c) => c.id == val).toList();
                          _selectedClassName = match.isNotEmpty ? match.first.className : '';
                        });
                        _loadAnalyticsReport();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loadAnalyticsReport,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Raporu Yenile'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOverviewStats(bool isMobile) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final dateRangeStr = (_report!.earliestDate != null && _report!.latestDate != null)
        ? '${dateFormat.format(_report!.earliestDate!)} — ${dateFormat.format(_report!.latestDate!)}'
        : 'Tüm Zamanlar';

    if (isMobile) {
      return Column(
        children: [
          _buildStatCard(
            title: 'Analiz Edilen Plan',
            value: '${_report!.totalPlansAnalyzed}',
            subtitle: 'Kayıtlı oturma düzeni',
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF5C6BC0),
          ),
          const SizedBox(height: 10),
          _buildStatCard(
            title: 'Analiz Edilen Öğrenci',
            value: '${_report!.studentAnalytics.length}',
            subtitle: 'Kayıtlı aktif öğrenci',
            icon: Icons.person_rounded,
            color: const Color(0xFF00897B),
          ),
          const SizedBox(height: 10),
          _buildStatCard(
            title: 'Tarih Aralığı',
            value: dateRangeStr,
            subtitle: 'İncelenen dönem',
            icon: Icons.date_range_rounded,
            color: const Color(0xFF7E57C2),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Analiz Edilen Plan',
            value: '${_report!.totalPlansAnalyzed}',
            subtitle: 'Kayıtlı oturma düzeni',
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF5C6BC0),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'Analiz Edilen Öğrenci',
            value: '${_report!.studentAnalytics.length}',
            subtitle: 'Kayıtlı aktif öğrenci',
            icon: Icons.person_rounded,
            color: const Color(0xFF00897B),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'Tarih Aralığı',
            value: dateRangeStr,
            subtitle: 'İncelenen dönem',
            icon: Icons.date_range_rounded,
            color: const Color(0xFF7E57C2),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmapCard(bool isMobile) {
    int maxUsage = 1;
    for (var count in _report!.classroomHeatmap.values) {
      if (count > maxUsage) maxUsage = count;
    }

    final double cellWidth = isMobile ? 68.0 : 80.0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heatmap Header & Legend
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.grid_on_rounded, color: Color(0xFF5C6BC0), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Sınıf Oturma Isı Haritası',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Düşük', style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600)),
                      const SizedBox(width: 4),
                      _buildLegendSquare(Colors.blue.shade50),
                      _buildLegendSquare(Colors.blue.shade200),
                      _buildLegendSquare(const Color(0xFF5C6BC0)),
                      _buildLegendSquare(const Color(0xFF6A1B9A)),
                      const SizedBox(width: 4),
                      Text('Yüksek', style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.grid_on_rounded, color: Color(0xFF5C6BC0)),
                      const SizedBox(width: 10),
                      Text(
                        'Sınıf Oturma Isı Haritası (Heatmap)',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Düşük', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                      const SizedBox(width: 4),
                      _buildLegendSquare(Colors.blue.shade50),
                      _buildLegendSquare(Colors.blue.shade200),
                      _buildLegendSquare(const Color(0xFF5C6BC0)),
                      _buildLegendSquare(const Color(0xFF6A1B9A)),
                      const SizedBox(width: 4),
                      Text('Yüksek', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              'Her masanın dönem boyunca toplam kaç kez kullanıldığını gösterir. Koyu renkler daha sık oturulan masaları temsil eder.',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),

            // Horizontal Scrollable Classroom Layout
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Blackboard Banner
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF37474F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'YAZI TAHTASI / KÜRSÜ',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Heatmap Grid
                    for (int r = 0; r < _report!.maxRow; r++) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text('${r + 1}. Sıra', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600)),
                          ),
                          const SizedBox(width: 8),
                          for (int c = 0; c < _report!.maxCol; c++) ...[
                            SizedBox(
                              width: cellWidth,
                              child: _buildHeatmapCell(r, c, maxUsage),
                            ),
                            if (c < _report!.maxCol - 1) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      if (r < _report!.maxRow - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendSquare(Color color) {
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
  }

  Widget _buildHeatmapCell(int row, int col, int maxUsage) {
    final count = _report!.classroomHeatmap['$row-$col'] ?? 0;
    final ratio = count / maxUsage;

    Color bgColor = Colors.grey.shade100;
    Color textColor = Colors.grey.shade800;

    if (count > 0) {
      if (ratio < 0.25) {
        bgColor = const Color(0xFFE8EAF6);
        textColor = const Color(0xFF3949AB);
      } else if (ratio < 0.5) {
        bgColor = const Color(0xFF9FA8DA);
        textColor = Colors.white;
      } else if (ratio < 0.75) {
        bgColor = const Color(0xFF5C6BC0);
        textColor = Colors.white;
      } else {
        bgColor = const Color(0xFF6A1B9A);
        textColor = Colors.white;
      }
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Masa ${row + 1}-${col + 1}',
            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.85)),
          ),
          const SizedBox(height: 2),
          Text(
            '$count kez',
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentAnalyticsSection(bool isMobile) {
    var list = _report!.studentAnalytics;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) =>
          s.studentName.toLowerCase().contains(q) ||
          (s.studentNumber != null && s.studentNumber!.contains(q))).toList();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics_rounded, color: Color(0xFF5C6BC0), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Öğrenci Analizleri (${list.length})',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Öğrenci veya numara ara...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics_rounded, color: Color(0xFF5C6BC0)),
                      const SizedBox(width: 10),
                      Text(
                        'Öğrenci Bazlı Oturma Koordinat Geçmişi & Analizleri',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Öğrenci ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),

            // Student Cards
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final student = list[index];
                return _buildStudentDetailRow(student);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentDetailRow(StudentSeatingAnalytics student) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: student.gender == 'K' ? Colors.pink.shade50 : Colors.blue.shade50,
                child: Text(
                  student.studentName.isNotEmpty ? student.studentName[0] : '?',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: student.gender == 'K' ? Colors.pink.shade700 : Colors.blue.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.studentName,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    if (student.studentNumber != null)
                      Text('Öğrenci No: #${student.studentNumber}',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              // Front Row badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF5C6BC0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ön Sıra: %${student.frontRowPercentage.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF3949AB)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Most frequent coordinate & neighbor
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place_rounded, size: 14, color: Colors.indigo),
                  const SizedBox(width: 4),
                  Text('En Sık Oturduğu: ', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade700)),
                  Text(student.mostFrequentCoordinate, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_alt_rounded, size: 14, color: Colors.teal),
                  const SizedBox(width: 4),
                  Text('En Sık Sıra Arkadaşı: ', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade700)),
                  Text(student.mostFrequentNeighbor, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Coordinate Breakdown Chips
          Text('Koordinat Dağılımı (Dönem Boyunca):',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: student.coordinateCounts.entries.map((e) {
              final label = student.coordinateLabels[e.key] ?? e.key;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '$label: ${e.value}x',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Bu şube için henüz kaydedilmiş oturma planı bulunamadı.',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Oturma planları oluşturulup kaydedildikçe tarihsel analitikler burada görüntülenecektir.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
