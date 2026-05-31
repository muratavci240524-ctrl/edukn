import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
              PopupMenuButton<String?>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _filterGrade != null
                        ? Colors.orange.shade50
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list_rounded,
                          size: 18,
                          color: _filterGrade != null
                              ? _primaryColor
                              : Colors.grey.shade500),
                      if (_filterGrade != null)
                        Text(' $_filterGrade.',
                            style: TextStyle(
                                color: _primaryColor, fontSize: 12)),
                    ],
                  ),
                ),
                onSelected: (v) => setState(() => _filterGrade = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Tüm Sınıflar')),
                  ...widget.exam.gradeLevels.map((g) =>
                      PopupMenuItem(value: g, child: Text('$g. Sınıf'))),
                ],
              ),
              const SizedBox(width: 8),
              // Excel export placeholder
              IconButton(
                onPressed: () => _showExportInfo(context),
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

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: regs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _buildRegCard(regs[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRegCard(ExternalExamRegistration reg) {
    final statusColors = {
      RegistrationStatus.pending: (Colors.orange.shade50, Colors.orange.shade700),
      RegistrationStatus.confirmed: (Colors.green.shade50, Colors.green.shade700),
      RegistrationStatus.cancelled: (Colors.red.shade50, Colors.red.shade600),
    };
    final (bg, fg) = statusColors[reg.status]!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
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
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        reg.statusName,
                        style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.bold, color: fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${reg.gradeLevel}. Sınıf · ${reg.currentSchool} · ${reg.displayTcNo}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey.shade500),
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
          PopupMenuButton<RegistrationStatus>(
            icon: Icon(Icons.more_vert_rounded,
                size: 18, color: Colors.grey.shade400),
            onSelected: (status) =>
                _service.updateRegistrationStatus(reg.id!, status),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: RegistrationStatus.confirmed,
                child: Text('Onayla'),
              ),
              const PopupMenuItem(
                value: RegistrationStatus.cancelled,
                child: Text('İptal Et'),
              ),
              const PopupMenuItem(
                value: RegistrationStatus.pending,
                child: Text('Bekleyene Al'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showExportInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Excel dışa aktarma özelliği yakında eklenecek.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
