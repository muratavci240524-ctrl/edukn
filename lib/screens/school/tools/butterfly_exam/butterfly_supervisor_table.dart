import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../services/butterfly_supervisor_table_data.dart';

/// Sınav planındaki salon x oturum/devre gözetmen çizelgesini alttan açılan geniş bir menüde gösterir.
/// - Satırlar: salonlar (küçükten büyüğe)
/// - Sütunlar: oturumlar ve (varsa) devreler, saat saat
/// - Salona özel bölünmüş devreler, o salonun hücresinde ayrı ayrı görünür.
Future<void> showSupervisorTableSheet(
  BuildContext context,
  ExamDistribution exam, {
  VoidCallback? onPdf,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SupervisorTableSheet(exam: exam, onPdf: onPdf),
  );
}

class _SupervisorTableSheet extends StatelessWidget {
  final ExamDistribution exam;
  final VoidCallback? onPdf;
  const _SupervisorTableSheet({required this.exam, this.onPdf});

  static const double _roomW = 84;
  static const double _gapW = 12;
  static const double _headATitleH = 50;
  static const double _headBH = 32;
  static const double _rowH = 54;
  static const double _minColW = 128;
  static const double _minSessionW = 190;
  static const double _pad = 16;

  @override
  Widget build(BuildContext context) {
    final data = SupervisorTableData.from(exam);
    final size = MediaQuery.of(context).size;
    final dateStr = DateFormat('dd.MM.yyyy').format(exam.examDate);
    final isNarrow = size.width < 600;

    return Container(
      width: double.infinity,
      height: size.height * 0.94,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, 10, 8, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF312E81), Color(0xFF4F46E5)]),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.table_chart_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gözetmen Listesi',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '${exam.title} • $dateStr • ${data.rooms.length} salon • ${data.assignedCells}/${data.totalCells} görev atanmış',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: const Color(0xFFC7D2FE), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    if (onPdf != null)
                      isNarrow
                          ? IconButton(
                              tooltip: 'PDF İndir / Paylaş',
                              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                              onPressed: onPdf,
                            )
                          : Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF3730A3),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                label: Text(
                                  'PDF İndir / Paylaş',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12.5),
                                ),
                                onPressed: onPdf,
                              ),
                            ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: data.rooms.isEmpty
                ? Center(
                    child: Text(
                      'Bu sınav planında salon bulunamadı.',
                      style: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final totalCols = data.totalColumns < 1 ? 1 : data.totalColumns;
                      final gaps = (data.sessions.length - 1) * _gapW;
                      final avail = constraints.maxWidth - _pad * 2 - _roomW - gaps;
                      final baseUnit = avail / totalCols;
                      final unit = baseUnit < _minColW ? _minColW : baseUnit;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(_pad),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRoomColumn(data),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildGrid(data, unit),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              top: false,
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _legend(const Color(0xFFEEF2FF), const Color(0xFFA5B4FC), 'Atanmış gözetmen'),
                  _legend(const Color(0xFFF5F3FF), const Color(0xFFC4B5FD), 'Salona özel bölünmüş devre'),
                  _legend(const Color(0xFFFEF2F2), const Color(0xFFFCA5A5), 'Gözetmen atanmamış'),
                  _legend(const Color(0xFFFFFBEB), const Color(0xFFFCD34D), 'Ara'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color bg, Color border, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569))),
      ],
    );
  }

  Widget _buildRoomColumn(SupervisorTableData data) {
    final rooms = data.rooms;
    return Column(
      children: [
        Container(
          width: _roomW,
          height: _headATitleH + _headBH,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
          ),
          child: Text(
            'SALON',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ),
        for (int i = 0; i < rooms.length; i++)
          Container(
            width: _roomW,
            height: _rowH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i.isEven ? const Color(0xFFF1F5F9) : const Color(0xFFE2E8F0),
              border: const Border(bottom: BorderSide(color: Colors.white, width: 1.5)),
              borderRadius: i == rooms.length - 1
                  ? const BorderRadius.only(bottomLeft: Radius.circular(12))
                  : null,
            ),
            child: Text(
              rooms[i].classroomName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(SupervisorTableData data, double unit) {
    final sessions = data.sessions;
    // Her oturumun sütun genişliği: başlık sığsın diye gerekirse büyütülür
    double unitFor(SupSession s) {
      final need = _minSessionW / s.columns.length;
      return unit > need ? unit : need;
    }

    final List<Widget> sessionHeads = [];
    final List<Widget> timeHeads = [];
    for (int si = 0; si < sessions.length; si++) {
      final s = sessions[si];
      final u = unitFor(s);
      sessionHeads.add(Container(
        width: s.columns.length * u,
        height: _headATitleH,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF4F46E5),
          border: Border(right: BorderSide(color: Colors.white, width: 1.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              s.title,
              textAlign: TextAlign.center,
              softWrap: true,
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            const SizedBox(height: 2),
            Text(
              '${SupervisorTableData.fmt(s.start)} - ${SupervisorTableData.fmt(s.end)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFFC7D2FE),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ));
      for (final c in s.columns) {
        timeHeads.add(Container(
          width: u,
          height: _headBH,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFE0E7FF),
            border: Border(right: BorderSide(color: Colors.white, width: 1.5)),
          ),
          child: Text(
            '${SupervisorTableData.fmt(c.start)} - ${SupervisorTableData.fmt(c.end)}',
            style: GoogleFonts.inter(
              color: const Color(0xFF3730A3),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ));
      }
      if (si < sessions.length - 1) {
        sessionHeads.add(_gapCell(_headATitleH));
        timeHeads.add(_gapCell(_headBH));
      }
    }

    final List<Widget> rowWidgets = [
      Row(children: sessionHeads),
      Row(children: timeHeads),
    ];

    for (int ri = 0; ri < data.rooms.length; ri++) {
      final room = data.rooms[ri];
      final List<Widget> cells = [];
      for (int si = 0; si < sessions.length; si++) {
        final s = sessions[si];
        final u = unitFor(s);
        for (final cell in data.cellsFor(room, s)) {
          cells.add(_dutyCell(
            width: data.spanOf(s, cell.seg) * u,
            name: cell.name,
            custom: cell.custom,
          ));
        }
        if (si < sessions.length - 1) cells.add(_gapCell(_rowH));
      }
      rowWidgets.add(Row(children: cells));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rowWidgets);
  }

  Widget _gapCell(double h) {
    return Container(width: _gapW, height: h, color: const Color(0xFFFFFBEB));
  }

  Widget _dutyCell({required double width, required String name, required bool custom}) {
    final bool has = name.isNotEmpty;
    final Color bg = has
        ? (custom ? const Color(0xFFF5F3FF) : const Color(0xFFEEF2FF))
        : const Color(0xFFFEF2F2);
    final Color border = has
        ? (custom ? const Color(0xFFC4B5FD) : const Color(0xFFA5B4FC))
        : const Color(0xFFFCA5A5);
    return Container(
      width: width,
      height: _rowH,
      padding: const EdgeInsets.all(2.5),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Text(
          has ? name : '—',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: has ? FontWeight.w700 : FontWeight.w500,
            color: has ? const Color(0xFF1E293B) : const Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }
}
