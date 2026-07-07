import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';
import '../../../../services/external_exam_service.dart';

class ExternalExamRegistrationsTab extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;

  const ExternalExamRegistrationsTab({
    Key? key,
    required this.exam,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ExternalExamRegistrationsTab> createState() =>
      _ExternalExamRegistrationsTabState();
}

class _ExternalExamRegistrationsTabState
    extends State<ExternalExamRegistrationsTab> {
  final ExternalExamService _service = ExternalExamService();
  String _searchQuery = '';
  String? _filterGrade;
  RegistrationStatus? _filterStatus;
  String? _filterSessionId;
  bool _showFilters = false;
  bool _isSaving = false;
  final Set<String> _selectedRegistrations = {};

  static const _primaryColor = Color(0xFFF57C00);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Column(
      children: [
        // Filter bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Ad, soyad veya TC ara...',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.grey.shade400, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _primaryColor, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _showFilters || _filterGrade != null || _filterSessionId != null
                        ? Colors.orange.shade50
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: _showFilters || _filterGrade != null || _filterSessionId != null
                        ? _primaryColor
                        : Colors.grey.shade500,
                  ),
                ),
                tooltip: 'Filtreler',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _pickAndImportExcel,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Icon(Icons.upload_file_rounded,
                      size: 18, color: Colors.blue.shade700),
                ),
                tooltip: 'Excel İle Başvuru Yükle',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _showExistingStudentsDialog,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Icon(Icons.person_add_alt_1_rounded,
                      size: 18, color: Colors.orange.shade700),
                ),
                tooltip: 'Mevcut Öğrencilerden Ekle',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              // Excel export
              IconButton(
                onPressed: _exportToExcel,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Icon(Icons.download_rounded,
                      size: 18, color: Colors.green.shade700),
                ),
                tooltip: 'Excel İndir',
                padding: EdgeInsets.zero,
              ),
            ],
            ),
        ),

        // Filter Panel
        if (_showFilters)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Sınıf Seviyesi:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Tümü'),
                            selected: _filterGrade == null,
                            onSelected: (val) => setState(() => _filterGrade = null),
                            selectedColor: Colors.orange.shade100,
                            labelStyle: TextStyle(color: _filterGrade == null ? Colors.orange.shade800 : Colors.grey.shade700),
                          ),
                          ...widget.exam.gradeLevels.map((g) => ChoiceChip(
                                label: Text(g == 'Mezun' ? 'Mezun' : '$g. Sınıf'),
                                selected: _filterGrade == g,
                                onSelected: (val) => setState(() => _filterGrade = val ? g : null),
                                selectedColor: Colors.orange.shade100,
                                labelStyle: TextStyle(color: _filterGrade == g ? Colors.orange.shade800 : Colors.grey.shade700),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.exam.applicationSessions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text('Seanslar:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Tümü'),
                              selected: _filterSessionId == null,
                              onSelected: (val) => setState(() => _filterSessionId = null),
                              selectedColor: Colors.orange.shade100,
                              labelStyle: TextStyle(color: _filterSessionId == null ? Colors.orange.shade800 : Colors.grey.shade700),
                            ),
                            ...widget.exam.applicationSessions.map((s) => ChoiceChip(
                                  label: Text('${s.sessionDate.day.toString().padLeft(2, '0')}.${s.sessionDate.month.toString().padLeft(2, '0')}.${s.sessionDate.year} - ${s.startTime}'),
                                  selected: _filterSessionId == s.id,
                                  onSelected: (val) => setState(() => _filterSessionId = val ? s.id : null),
                                  selectedColor: Colors.orange.shade100,
                                  labelStyle: TextStyle(color: _filterSessionId == s.id ? Colors.orange.shade800 : Colors.grey.shade700),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (_showFilters) const Divider(height: 1),

        // List
        Expanded(
          child: StreamBuilder<List<ExternalExamRegistration>>(
            stream: _service.getRegistrations(widget.exam.id ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _primaryColor));
              }

              var regs = snapshot.data ?? [];

              // Apply filters
              if (_filterGrade != null) {
                regs = regs.where((r) => r.gradeLevel == _filterGrade).toList();
              }
              if (_filterSessionId != null) {
                regs = regs.where((r) => r.sessionId == _filterSessionId).toList();
              }
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                regs = regs
                    .where((r) =>
                        r.fullName.toLowerCase().contains(q) ||
                        r.studentTcNo.contains(q) ||
                        r.currentSchool.toLowerCase().contains(q))
                    .toList();
              }

              if (regs.isEmpty) {
                return Center(
                  child: Text(
                    _searchQuery.isNotEmpty || _filterGrade != null
                        ? 'Arama sonucu bulunamadı.'
                        : 'Henüz başvuru yok.',
                    style: GoogleFonts.inter(color: Colors.grey.shade500),
                  ),
                );
              }

              // Başvuru tarihine göre sırala (en yeni başta)
              regs = List.from(regs)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              final allIds = regs.where((r) => r.id != null).map((r) => r.id!).toList();
              final isAllSelected = allIds.isNotEmpty && _selectedRegistrations.length == allIds.length;
              final isAnySelected = _selectedRegistrations.isNotEmpty;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isAllSelected,
                          tristate: isAnySelected && !isAllSelected,
                          activeColor: _primaryColor,
                          onChanged: (val) {
                            setState(() {
                              if (val == true || val == null) {
                                _selectedRegistrations.addAll(allIds);
                              } else {
                                _selectedRegistrations.clear();
                              }
                            });
                          },
                        ),
                        Text('Tümünü Seç (${regs.length})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                        const Spacer(),
                        if (isAnySelected)
                          ElevatedButton.icon(
                            onPressed: () => _deleteSelectedRegistrations(),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: Text('${_selectedRegistrations.length} Başvuruyu Kaldır'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red.shade700,
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: regs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _buildRegCard(regs[i]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_isSaving)
          const LinearProgressIndicator(color: _primaryColor),
      ],
    );
  }

  Future<void> _deleteSelectedRegistrations() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçili Başvuruları Kaldır'),
        content: Text('Seçili ${_selectedRegistrations.length} başvuruyu kalıcı olarak kaldırmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Evet, Kaldır'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      try {
        // Firestore batch ile tek seferde sil (çok hızlı)
        const batchLimit = 500;
        final ids = _selectedRegistrations.toList();
        for (int i = 0; i < ids.length; i += batchLimit) {
          final batch = FirebaseFirestore.instance.batch();
          final chunk = ids.sublist(i, (i + batchLimit).clamp(0, ids.length));
          for (final id in chunk) {
            batch.delete(
              FirebaseFirestore.instance
                  .collection('external_exam_registrations')
                  .doc(id),
            );
          }
          await batch.commit();
        }
        setState(() {
          _selectedRegistrations.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seçili başvurular kaldırıldı.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildRegCard(ExternalExamRegistration reg) {

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEditRegistrationDialog(reg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
        children: [
          if (reg.id != null)
            Checkbox(
              value: _selectedRegistrations.contains(reg.id),
              activeColor: _primaryColor,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedRegistrations.add(reg.id!);
                  } else {
                    _selectedRegistrations.remove(reg.id!);
                  }
                });
              },
            ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                reg.studentName.isNotEmpty
                    ? reg.studentName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                    fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reg.fullName,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade800),
                      ),
                    ),
                    Text(
                      '${reg.createdAt.day.toString().padLeft(2,'0')}.${reg.createdAt.month.toString().padLeft(2,'0')}.${reg.createdAt.year} ${reg.createdAt.hour.toString().padLeft(2,'0')}:${reg.createdAt.minute.toString().padLeft(2,'0')}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${reg.gradeLevel == 'Mezun' ? 'Mezun' : '${reg.gradeLevel}. Sınıf'}${reg.parentName != null && reg.parentName!.isNotEmpty ? ' · Veli: ${reg.parentName}' : ''}${reg.parentPhone != null && reg.parentPhone!.isNotEmpty ? ' - ${reg.parentPhone}' : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.grey.shade500),
                ),
                if (reg.assignedRoomName != null)
                  Text(
                    '🏫 ${reg.assignedRoomName} – ${reg.seatNumber}. sıra',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.green.shade600),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                size: 18, color: Colors.grey.shade400),
            onSelected: (value) async {
              if (value == 'edit') {
                _showEditRegistrationDialog(reg);
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Başvuruyu Sil'),
                    content: const Text('Bu başvuruyu kalıcı olarak silmek istediğinize emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('İptal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sil', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && reg.id != null) {
                  try {
                    await _service.deleteRegistration(reg.id!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Başvuru silindi.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Silme hatası: $e')),
                      );
                    }
                  }
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Düzenle'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Başvuruyu Kaldır', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
            ],
          ), // closes Row
        ), // closes Padding
      ), // closes InkWell
      ), // closes Material
    ); // closes Container
  }

  Future<void> _exportToExcel() async {
    try {
      final regs = await _service.getRegistrations(widget.exam.id ?? '').first;
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Başvurular'];
      excel.setDefaultSheet('Başvurular');

      // Headers
      List<String> headers = [
        'StudentName',
        'StudentSurname',
        'StudentTcNo',
        'StudentNumber',
        'GradeLevel',
        'ParentName',
        'ParentSurname',
        'ParentPhone',
        'ParentEmail',
        'City',
        'District',
        'CurrentSchool',
        'SessionId'
      ];
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (var reg in regs) {
        List<CellValue> row = [
          TextCellValue(reg.studentName),
          TextCellValue(reg.studentSurname),
          TextCellValue(reg.studentTcNo),
          TextCellValue(reg.studentNumber ?? ''),
          TextCellValue(reg.gradeLevel),
          TextCellValue(reg.parentName ?? ''),
          TextCellValue(reg.parentSurname ?? ''),
          TextCellValue(reg.parentPhone ?? ''),
          TextCellValue(reg.parentEmail ?? ''),
          TextCellValue(reg.city ?? ''),
          TextCellValue(reg.district ?? ''),
          TextCellValue(reg.currentSchool),
          TextCellValue(reg.sessionId ?? ''),
        ];
        sheetObject.appendRow(row);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      var fileBytes = excel.encode();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Basvurular_${widget.exam.title.replaceAll(' ', '_')}',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel başarıyla indirildi.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel indirme hatası: $e')),
        );
      }
    }
  }

  Future<void> _pickAndImportExcel() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      
      var excel = Excel.decodeBytes(file.bytes!);
      var sheet = excel.tables[excel.tables.keys.first];
      
      if (sheet == null || sheet.maxRows < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel dosyası boş veya geçersiz.')),
          );
        }
        return;
      }

      List<String> header = [];
      for (var cell in sheet.row(0)) {
        header.add(cell?.value?.toString().toLowerCase().trim() ?? '');
      }

      final expected = ['studentname', 'studentsurname', 'studenttcno', 'studentnumber', 'gradelevel', 'parentname', 'parentsurname', 'parentphone', 'parentemail', 'city', 'district', 'currentschool'];
      for (final col in expected) {
        if (!header.contains(col)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Excel başlık eksik: $col. Lütfen indirdiğiniz Excel formatını kullanın.')),
            );
          }
          return;
        }
      }

      List<ExternalExamRegistration> pendingRegistrations = [];

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.row(i);
        // check if row is empty
        if (row.every((cell) => cell?.value == null || cell!.value.toString().trim().isEmpty)) continue;

        Map<String, dynamic> map = {};
        for (int j = 0; j < header.length; j++) {
          if (j < row.length) {
            map[header[j]] = row[j]?.value?.toString().trim() ?? '';
          } else {
            map[header[j]] = '';
          }
        }

        final registration = ExternalExamRegistration(
          examId: widget.exam.id ?? '',
          institutionId: widget.exam.institutionId,
          sessionId: map['sessionid']?.toString().isNotEmpty == true
                ? map['sessionid']!.toString()
                : (widget.exam.applicationSessions.isNotEmpty ? widget.exam.applicationSessions.first.id : ''),
          studentName: map['studentname']?.toString() ?? '',
          studentSurname: map['studentsurname']?.toString() ?? '',
          studentTcNo: map['studenttcno']?.toString() ?? '',
          studentNumber: map['studentnumber']?.toString(),
          gradeLevel: map['gradelevel']?.toString() ?? '',
          parentName: map['parentname']?.toString() ?? '',
          parentSurname: map['parentsurname']?.toString() ?? '',
          parentPhone: map['parentphone']?.toString() ?? '',
          parentEmail: map['parentemail']?.toString(),
          city: map['city']?.toString() ?? '',
          district: map['district']?.toString() ?? '',
          currentSchool: map['currentschool']?.toString() ?? '',
          phone: map['phone']?.toString(),
          email: map['email']?.toString(),
          registrationSource: RegistrationSource.manualExcel,
          status: RegistrationStatus.confirmed,
          createdAt: DateTime.now(),
        );
        pendingRegistrations.add(registration);
      }
      
      if (pendingRegistrations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eklenecek geçerli satır bulunamadı.')));
        }
        return;
      }

      // Sınıf seviyesi kırılımını hesapla
      Map<String, int> gradeBreakdown = {};
      for (var r in pendingRegistrations) {
        final g = r.gradeLevel.isNotEmpty ? r.gradeLevel : 'Belirtilmemiş';
        gradeBreakdown[g] = (gradeBreakdown[g] ?? 0) + 1;
      }

      String breakdownText = gradeBreakdown.entries
          .map((e) => '${e.key}. Sınıf: ${e.value} kişi')
          .join('\n');

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Excel İle Başvuru Yükleme'),
          content: Text(
            'Toplam ${pendingRegistrations.length} öğrenci yüklenecek.\n\n'
            'Sınıf Dağılımı:\n$breakdownText\n\n'
            'Onaylıyor musunuz?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Evet, Yükle'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      if (!mounted) return;

      // Animasyonlu ilerleme dialogu
      int uploaded = 0;
      final total = pendingRegistrations.length;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.upload_file_rounded, color: _primaryColor),
                  const SizedBox(width: 12),
                  Text('Yükleniyor...', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ],
              ),
              content: StatefulBuilder(
                builder: (ctx2, setInner) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: total > 0 ? uploaded / total : 0),
                        duration: const Duration(milliseconds: 400),
                        builder: (_, val, __) => LinearProgressIndicator(
                          value: val,
                          backgroundColor: Colors.grey.shade200,
                          color: _primaryColor,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$uploaded / $total öğrenci yüklendi',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      );

      try {
        // Batch ile yükle (500'lük gruplar halinde)
        const batchLimit = 500;
        for (int i = 0; i < pendingRegistrations.length; i += batchLimit) {
          final batch = FirebaseFirestore.instance.batch();
          final chunk = pendingRegistrations.sublist(
            i, (i + batchLimit).clamp(0, pendingRegistrations.length));
          for (final r in chunk) {
            final docRef = FirebaseFirestore.instance
                .collection('external_exam_registrations')
                .doc();
            batch.set(docRef, r.toMap());
          }
          await batch.commit();
          uploaded = (i + chunk.length).clamp(0, total);
        }

        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$total öğrenci başarıyla yüklendi.')),
          );
        }
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel import hatası: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel import hatası: $e')),
        );
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showEditRegistrationDialog(ExternalExamRegistration reg) {
    showDialog(
      context: context,
      builder: (context) => _EditRegistrationDialog(
        registration: reg,
        service: _service,
      ),
    );
  }

  void _showExistingStudentsDialog() {
    showDialog(
      context: context,
      builder: (context) => _ExistingStudentsDialog(
        exam: widget.exam,
        service: _service,
      ),
    );
  }
}

class _ExistingStudentsDialog extends StatefulWidget {
  final ExternalExam exam;
  final ExternalExamService service;

  const _ExistingStudentsDialog({
    Key? key,
    required this.exam,
    required this.service,
  }) : super(key: key);

  @override
  State<_ExistingStudentsDialog> createState() => _ExistingStudentsDialogState();
}

class _ExistingStudentsDialogState extends State<_ExistingStudentsDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allStudents = [];
  Map<String, List<Map<String, dynamic>>> _groupedStudents = {};
  Map<String, List<Map<String, dynamic>>> _filteredGroupedStudents = {};
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      // venueConfig.schoolTypeIds sınavın hangi okul türlerini kapsadığını gösterir
      final schoolTypeIds = widget.exam.venueConfig.schoolTypeIds;

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.exam.institutionId)
          .where('isActive', isEqualTo: true);

      final snapshot = await query.get();

      List<Map<String, dynamic>> students = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Eğer schoolTypeIds doluysa client-side filtrele
      if (schoolTypeIds.isNotEmpty) {
        students = students
            .where((s) => schoolTypeIds.contains(s['schoolTypeId']?.toString()))
            .toList();
      }

      // Sort by name
      students.sort((a, b) {
        final nameA = (a['fullName'] ?? a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['fullName'] ?? b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });

      _allStudents = students;
      _groupAndFilterStudents('');
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Öğrenciler yüklenemedi: $e')),
        );
      }
    }
  }

  void _groupAndFilterStudents(String query) {
    _searchQuery = query.toLowerCase();
    
    // First, filter all students
    final filtered = _allStudents.where((s) {
      final name = (s['fullName'] ?? s['name'] ?? '').toString().toLowerCase();
      final tc = (s['tcIdentityNumber'] ?? s['tcNo'] ?? s['tcKimlik'] ?? '').toString();
      final studentNo = (s['studentNumber'] ?? s['schoolNumber'] ?? s['studentNo'] ?? '').toString();
      return name.contains(_searchQuery) || tc.contains(_searchQuery) || studentNo.contains(_searchQuery);
    }).toList();

    // Group them
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final s in filtered) {
      // Try to determine class or grade level
      String clsName = s['classLevel']?.toString() ?? s['grade']?.toString() ?? s['class']?.toString() ?? '';
      if (clsName.isEmpty) {
        clsName = 'Diğer Sınıflar';
      } else {
        // If it's just a number like "8", format it as "8. Sınıf"
        if (RegExp(r'^\d+$').hasMatch(clsName)) {
          clsName = '$clsName. Sınıf';
        } else if (RegExp(r'^\d+').hasMatch(clsName) && !clsName.toLowerCase().contains('sınıf')) {
            // E.g. "8A" -> "8. Sınıf" or group by branch? The user asked for "8. Sınıf", let's group by whatever is provided.
            // Just use the provided class string.
        }
      }
      
      if (!grouped.containsKey(clsName)) {
        grouped[clsName] = [];
      }
      grouped[clsName]!.add(s);
    }

    // Sort groups so that "8. Sınıf" comes before "9. Sınıf" etc.
    final sortedGrouped = Map.fromEntries(
      grouped.entries.toList()..sort((a, b) {
        if (a.key == 'Diğer Sınıflar') return 1;
        if (b.key == 'Diğer Sınıflar') return -1;
        
        // Extract numbers for sorting
        final numA = int.tryParse(RegExp(r'\d+').firstMatch(a.key)?.group(0) ?? '') ?? 0;
        final numB = int.tryParse(RegExp(r'\d+').firstMatch(b.key)?.group(0) ?? '') ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.key.compareTo(b.key);
      })
    );

    setState(() {
      _filteredGroupedStudents = sortedGrouped;
      _isLoading = false;
    });
  }

  void _filterStudents(String query) {
    _groupAndFilterStudents(query);
  }

  void _toggleGroupSelection(String groupName, bool? value) {
    if (value == null) return;
    setState(() {
      final studentsInGroup = _filteredGroupedStudents[groupName] ?? [];
      if (value) {
        for (var s in studentsInGroup) {
          _selectedIds.add(s['id']);
        }
      } else {
        for (var s in studentsInGroup) {
          _selectedIds.remove(s['id']);
        }
      }
    });
  }

  bool _isGroupFullySelected(String groupName) {
    final studentsInGroup = _filteredGroupedStudents[groupName] ?? [];
    if (studentsInGroup.isEmpty) return false;
    return studentsInGroup.every((s) => _selectedIds.contains(s['id']));
  }

  bool _isGroupPartiallySelected(String groupName) {
    final studentsInGroup = _filteredGroupedStudents[groupName] ?? [];
    if (studentsInGroup.isEmpty) return false;
    final selectedCount = studentsInGroup.where((s) => _selectedIds.contains(s['id'])).length;
    return selectedCount > 0 && selectedCount < studentsInGroup.length;
  }

  Future<void> _saveSelected() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final selectedStudents = _allStudents.where((s) => _selectedIds.contains(s['id'])).toList();
      final registrations = selectedStudents.map((user) {
        final nameParts = (user['fullName'] ?? user['name'] ?? 'İsimsiz').toString().split(' ');
        final surname = nameParts.length > 1 ? nameParts.last : '';
        final name = nameParts.length > 1 ? nameParts.sublist(0, nameParts.length - 1).join(' ') : nameParts.first;

        return ExternalExamRegistration(
          examId: widget.exam.id ?? '',
          institutionId: widget.exam.institutionId,
          sessionId: widget.exam.applicationSessions.isNotEmpty ? widget.exam.applicationSessions.first.id : '',
          studentName: name,
          studentSurname: surname,
          studentTcNo: (user['tcIdentityNumber'] ?? user['tcNo'] ?? user['tcKimlik'] ?? '').toString(),
          studentNumber: (user['studentNumber'] ?? user['schoolNumber'] ?? user['studentNo'])?.toString(),
          gradeLevel: (user['classLevel'] ?? user['grade'] ?? user['class'] ?? '').toString(),
          parentName: user['parentName']?.toString() ?? '',
          parentSurname: '',
          parentPhone: user['parentPhone']?.toString() ?? '',
          parentEmail: null,
          city: '',
          district: '',
          currentSchool: 'Kurum İçi Öğrenci',
          phone: user['phone']?.toString(),
          email: user['email']?.toString(),
          registrationSource: RegistrationSource.manualExcel,
          status: RegistrationStatus.confirmed,
          createdAt: DateTime.now(),
        );
      }).toList();

      // Firestore batch ile tek seferde kaydet
      const batchLimit = 500;
      for (int i = 0; i < registrations.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final chunk = registrations.sublist(
          i, (i + batchLimit).clamp(0, registrations.length));
        for (final r in chunk) {
          final docRef = FirebaseFirestore.instance
              .collection('external_exam_registrations')
              .doc();
          batch.set(docRef, r.toMap());
        }
        await batch.commit();
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${registrations.length} öğrenci başarıyla kaydedildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e')),
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.group_add_rounded, color: Colors.orange.shade700),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mevcut Öğrencilerden Ekle',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Kurumunuzdaki öğrencileri sınava dahil edin',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: _filterStudents,
              decoration: InputDecoration(
                hintText: 'Öğrenci adı, TC veya numara ara...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredGroupedStudents.isEmpty
                      ? Center(
                          child: Text(
                            'Öğrenci bulunamadı',
                            style: GoogleFonts.inter(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredGroupedStudents.length,
                          itemBuilder: (context, index) {
                            final groupName = _filteredGroupedStudents.keys.elementAt(index);
                            final studentsInGroup = _filteredGroupedStudents[groupName]!;
                            
                            final isFullySelected = _isGroupFullySelected(groupName);
                            final isPartiallySelected = _isGroupPartiallySelected(groupName);
                            
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  title: Row(
                                    children: [
                                      Checkbox(
                                        value: isFullySelected ? true : (isPartiallySelected ? null : false),
                                        tristate: true,
                                        onChanged: (val) {
                                          if (val == null) {
                                            // From partial to full
                                            _toggleGroupSelection(groupName, true);
                                          } else {
                                            _toggleGroupSelection(groupName, val);
                                          }
                                        },
                                      ),
                                      Expanded(
                                        child: Text(
                                          groupName,
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${studentsInGroup.length} Öğrenci',
                                          style: GoogleFonts.inter(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  children: studentsInGroup.map((student) {
                                    final isSelected = _selectedIds.contains(student['id']);
                                    final name = student['fullName'] ?? student['name'] ?? 'İsimsiz';
                                    final tc = student['tcIdentityNumber'] ?? student['tcNo'] ?? '';
                                    
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: Border(top: BorderSide(color: Colors.grey.shade100)),
                                      ),
                                      child: CheckboxListTile(
                                        value: isSelected,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedIds.add(student['id']);
                                            } else {
                                              _selectedIds.remove(student['id']);
                                            }
                                          });
                                        },
                                        title: Text(name, style: GoogleFonts.inter(fontSize: 14)),
                                        subtitle: tc.isNotEmpty ? Text('TC: $tc', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)) : null,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedIds.length} öğrenci seçildi',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: Colors.orange.shade700),
                ),
                ElevatedButton(
                  onPressed: _selectedIds.isEmpty || _isSaving ? null : _saveSelected,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Seçilenleri Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRegistrationDialog extends StatefulWidget {
  final ExternalExamRegistration registration;
  final ExternalExamService service;

  const _EditRegistrationDialog({
    Key? key,
    required this.registration,
    required this.service,
  }) : super(key: key);

  @override
  State<_EditRegistrationDialog> createState() => _EditRegistrationDialogState();
}

class _EditRegistrationDialogState extends State<_EditRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _surnameCtrl;
  late TextEditingController _tcCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _gradeCtrl;
  late TextEditingController _schoolCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.registration.studentName);
    _surnameCtrl = TextEditingController(text: widget.registration.studentSurname);
    _tcCtrl = TextEditingController(text: widget.registration.studentTcNo);
    _phoneCtrl = TextEditingController(text: widget.registration.phone ?? widget.registration.parentPhone ?? '');
    _gradeCtrl = TextEditingController(text: widget.registration.gradeLevel);
    _schoolCtrl = TextEditingController(text: widget.registration.currentSchool);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _surnameCtrl.dispose();
    _tcCtrl.dispose();
    _phoneCtrl.dispose();
    _gradeCtrl.dispose();
    _schoolCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final updated = widget.registration.copyWith(
        studentName: _nameCtrl.text.trim(),
        studentSurname: _surnameCtrl.text.trim(),
        studentTcNo: _tcCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        gradeLevel: _gradeCtrl.text.trim(),
        currentSchool: _schoolCtrl.text.trim(),
      );
      await widget.service.updateRegistration(widget.registration.id!, updated);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Başvuru güncellendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 650,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.edit_document, color: Colors.blue.shade700, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Başvuruyu Düzenle',
                            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                          ),
                          Text(
                            'Öğrencinin kayıt bilgilerini güncelleyin',
                            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade400),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey.shade50),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _nameCtrl,
                        label: 'Öğrenci Adı',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _surnameCtrl,
                        label: 'Öğrenci Soyadı',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _tcCtrl,
                        label: 'TC Kimlik No',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _gradeCtrl,
                        label: 'Sınıf Seviyesi',
                        icon: Icons.school_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _phoneCtrl,
                        label: 'İletişim (Telefon)',
                        icon: Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _schoolCtrl,
                        label: 'Mevcut Okulu',
                        icon: Icons.account_balance_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Değişiklikleri Kaydet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
        ),
      ),
    );
  }
}


