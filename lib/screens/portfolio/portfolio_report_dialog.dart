import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import '../../services/portfolio_report_service.dart';
import '../../services/pdf_service.dart';
import 'package:file_saver/file_saver.dart';

class PortfolioReportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> filteredStudents;
  final Map<String, dynamic>? selectedStudent;
  final String institutionId;
  final String termId;
  final Map<String, dynamic> schoolSettings;

  const PortfolioReportDialog({
    Key? key,
    required this.filteredStudents,
    this.selectedStudent,
    required this.institutionId,
    required this.termId,
    required this.schoolSettings,
  }) : super(key: key);

  @override
  State<PortfolioReportDialog> createState() => _PortfolioReportDialogState();
}

class _PortfolioReportDialogState extends State<PortfolioReportDialog> {
  final PortfolioReportService _reportService = PortfolioReportService();
  final PdfService _pdfService = PdfService();

  bool _reportForAll = false;
  bool _startEachOnNewPage = true;
  bool _isProcessing = false;
  double _progress = 0;
  String _currentProcessingName = '';

  final Map<String, bool> _modules = {
    'genel': true,
    'deneme': true,
    'yazili': true,
    'odev': true,
    'devamsizlik': true,
    'etut': true,
    'kitap': true,
    'gorusme': false, // Private by default
    'gelisim': true,
    'calisma': true,
    'rehberlik': true,
    'etkinlik': true,
  };

  final Map<String, String> _moduleLabels = {
    'genel': 'Genel Bilgiler',
    'deneme': 'Deneme Sınavları',
    'yazili': 'Yazılı Sınavlar',
    'odev': 'Ödev Takibi',
    'devamsizlik': 'Devamsızlık',
    'etut': 'Etütler',
    'kitap': 'Kitaplar',
    'gorusme': 'Görüşme Notları (Özel)',
    'gelisim': 'Gelişim Raporları',
    'calisma': 'Çalışma Programı',
    'rehberlik': 'Rehberlik Testleri',
    'etkinlik': 'Etkinlik Raporları',
  };

  @override
  void initState() {
    super.initState();
    // Default to selected student if one is active
    if (widget.selectedStudent != null) {
      _reportForAll = false;
    } else {
      _reportForAll = true;
    }
  }

  Future<void> _handleAction(bool isPrint) async {
    setState(() {
      _isProcessing = true;
      _progress = 0;
    });

    // Ensure the loading dialog is fully rendered before starting heavy work
    await Future.delayed(const Duration(milliseconds: 150));

    final List<Map<String, dynamic>> targetStudents = _reportForAll 
        ? widget.filteredStudents 
        : [widget.selectedStudent!];

    final List<String> enabledModules = _modules.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    try {
      // 1. Pre-load Assets (Once for all)
      final ByteData logoData = await rootBundle.load('assets/images/logo.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      
      final baseFont = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      final italicFont = await PdfGoogleFonts.robotoItalic();

      if (!_reportForAll) {
        // SINGLE STUDENT
        _currentProcessingName = targetStudents.first['fullName'] ?? 'Öğrenci';
        
        // Give UI a chance to show the initial name
        await Future.delayed(const Duration(milliseconds: 100));

        final data = await _reportService.fetchFullPortfolioData(
          studentId: targetStudents.first['id'] ?? targetStudents.first['uid'],
          institutionId: widget.institutionId,
          termId: widget.termId,
        );
        
        // Final yielding before heavy PDF work
        await Future.delayed(const Duration(milliseconds: 100));

        final pdfBytes = await _pdfService.generateDetailedPortfolioPdf(
          studentData: data,
          enabledModules: enabledModules,
          startEachModuleOnNewPage: _startEachOnNewPage,
          schoolSettings: widget.schoolSettings,
          systemLogo: logoBytes,
          baseFont: baseFont,
          boldFont: boldFont,
          italicFont: italicFont,
        );

        if (isPrint) {
          await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
        } else {
          final fileName = "${targetStudents.first['classLevel'] ?? ''} ${_currentProcessingName} - Portfolyo Raporu";
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: pdfBytes,
            ext: 'pdf',
            mimeType: MimeType.pdf,
          );
        }
      } else {
        // BATCH STUDENTS
        List<Map<String, dynamic>> pdfFiles = [];
        for (int i = 0; i < targetStudents.length; i++) {
          final student = targetStudents[i];
          setState(() {
            _progress = (i + 1) / targetStudents.length;
            _currentProcessingName = student['fullName'] ?? 'Öğrenci';
          });

          // Yield to browser for animation smoothness
          await Future.delayed(const Duration(milliseconds: 150));

          // Extra yielding for responsiveness
          await Future.delayed(const Duration(milliseconds: 100));

          final data = await _reportService.fetchFullPortfolioData(
            studentId: student['id'] ?? student['uid'],
            institutionId: widget.institutionId,
            termId: widget.termId,
          );
          
          await Future.delayed(const Duration(milliseconds: 50));

          final pdfBytes = await _pdfService.generateDetailedPortfolioPdf(
            studentData: data,
            enabledModules: enabledModules,
            startEachModuleOnNewPage: _startEachOnNewPage,
            schoolSettings: widget.schoolSettings,
            systemLogo: logoBytes,
            baseFont: baseFont,
            boldFont: boldFont,
            italicFont: italicFont,
          );

          pdfFiles.add({
            'name': "${student['classLevel'] ?? ''} ${_currentProcessingName} - Portfolyo Raporu.pdf",
            'data': pdfBytes,
          });
        }

        final zipBytes = _reportService.generateZip(pdfFiles);
        await FileSaver.instance.saveFile(
          name: "Toplu Portfolyo Raporları",
          bytes: zipBytes,
          ext: 'zip',
          mimeType: MimeType.zip,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        // Give the UI thread a moment to settle after heavy PDF operation
        // and before closing the dialog to avoid mouse_tracker assertions
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: _isProcessing ? _buildProcessingView() : _buildSelectionView(),
      ),
    );
  }

  Widget _buildSelectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.print_rounded, color: Colors.indigo.shade900, size: 28),
            const SizedBox(width: 12),
            Text(
              'Portfolyo Raporu Oluştur',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Scope Selection
        Text('Kapsam Seçimi', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              RadioListTile<bool>(
                title: Text(widget.selectedStudent != null 
                  ? 'Seçili Öğrenci (${widget.selectedStudent!['fullName']})' 
                  : 'Seçili Öğrenci (Yok)', 
                  style: const TextStyle(fontSize: 14)),
                value: false,
                groupValue: _reportForAll,
                onChanged: widget.selectedStudent == null ? null : (v) => setState(() => _reportForAll = v!),
              ),
              RadioListTile<bool>(
                title: Text('Filtrelenmiş Tüm Öğrenciler (${widget.filteredStudents.length} Kişi)', style: const TextStyle(fontSize: 14)),
                value: true,
                groupValue: _reportForAll,
                onChanged: (v) => setState(() => _reportForAll = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Layout Toggle
        SwitchListTile(
          title: Text('Her bölümü yeni sayfadan başlat', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: const Text('Raporu daha ferah ama daha fazla sayfa yapar', style: TextStyle(fontSize: 11)),
          value: _startEachOnNewPage,
          onChanged: (v) => setState(() => _startEachOnNewPage = v),
          activeColor: Colors.indigo,
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        
        // Module Selection
        Text('Rapor İçerik Başlıkları', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 250,
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 4,
            children: _modules.keys.map((key) {
              return CheckboxListTile(
                title: Text(_moduleLabels[key]!, style: const TextStyle(fontSize: 12)),
                value: _modules[key],
                onChanged: (v) => setState(() => _modules[key] = v!),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _handleAction(false),
              icon: Icon(_reportForAll ? Icons.folder_zip_rounded : Icons.download_rounded),
              label: Text(_reportForAll ? 'ZIP Olarak İndir' : 'PDF İndir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 8),
            if (!_reportForAll)
              ElevatedButton.icon(
                onPressed: () => _handleAction(true),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Yazdır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        const EduKNLoadingAnimation(),
        const SizedBox(height: 32),
        Text(
          _reportForAll ? 'Toplu Rapor Hazırlanıyor...' : 'Rapor Hazırlanıyor...',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo.shade900),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Şu an işlemde: $_currentProcessingName',
            style: TextStyle(color: Colors.indigo.shade700, fontSize: 13, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
        if (_reportForAll) ...[
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progress, 
              backgroundColor: Colors.grey.shade200, 
              color: Colors.indigo,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text('%${(_progress * 100).toInt()} tamamlandı', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
        const SizedBox(height: 32),
        const Text(
          'Lütfen tarayıcıyı veya uygulamayı kapatmayın.',
          style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class EduKNLoadingAnimation extends StatefulWidget {
  const EduKNLoadingAnimation({Key? key}) : super(key: key);

  @override
  State<EduKNLoadingAnimation> createState() => _EduKNLoadingAnimationState();
}

class _EduKNLoadingAnimationState extends State<EduKNLoadingAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(3, (index) {
              final double start = index * 0.15;
              final double animValue = (_controller.value - start).clamp(0.0, 1.0);
              
              // Pulse logic: scaling and opacity based on sine wave for smoothness
              final double pulse = (math.sin((animValue * math.pi * 2) - (math.pi / 2)) + 1) / 2;
              
              return Positioned(
                left: 10.0 + (index * 25.0),
                child: Opacity(
                  opacity: 0.1 + (pulse * 0.9),
                  child: Transform.scale(
                    scale: 0.8 + (pulse * 0.4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Color.lerp(Colors.indigo.shade400, Colors.indigo.shade900, pulse),
                      size: 48,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// Helper for horizontal stacking in the animation
class CenterBy extends Alignment {
  const CenterBy(double x) : super(x, 0);
}
