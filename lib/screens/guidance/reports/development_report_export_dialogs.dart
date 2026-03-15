import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/guidance/development_report/development_report_session_model.dart';
import '../../../models/guidance/development_report/development_report_model.dart';
import 'development_report_pdf_helper.dart';

void showDevelopmentReportIndividualExport(
  BuildContext context,
  DevelopmentReportSession session,
) {
  showDialog(
    context: context,
    builder: (context) => _IndividualExportDialog(session: session),
  );
}

void showDevelopmentReportBulkExport(
  BuildContext context,
  DevelopmentReportSession session,
) {
  showDialog(
    context: context,
    builder: (context) => _BulkExportDialog(session: session),
  );
}

class _IndividualExportDialog extends StatefulWidget {
  final DevelopmentReportSession session;
  const _IndividualExportDialog({required this.session});

  @override
  __IndividualExportDialogState createState() =>
      __IndividualExportDialogState();
}

class __IndividualExportDialogState extends State<_IndividualExportDialog> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _allTargets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    try {
      final List<Map<String, dynamic>> loaded = [];
      final collectionName = widget.session.targetGroup == 'student'
          ? 'students'
          : 'users';

      // Chunking the targetIds
      final targetIds = widget.session.targetUserIds;
      for (var i = 0; i < targetIds.length; i += 10) {
        final chunk = targetIds.skip(i).take(10).toList();
        final snap = await FirebaseFirestore.instance
            .collection(collectionName)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in snap.docs) {
          final data = doc.data();
          String name =
              data['fullName'] ??
              data['name'] ??
              data['firstName'] ??
              'İsimsiz';
          if (data['lastName'] != null) name += ' ${data['lastName']}';
          loaded.add({'id': doc.id, 'name': name});
        }
      }

      loaded.sort(
        (a, b) => a['name'].toString().compareTo(b['name'].toString()),
      );

      if (mounted) {
        setState(() {
          _allTargets = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Kişiler yüklenirken hata oluştu: $e")),
        );
      }
    }
  }

  Future<void> _exportIndividualPdf(String targetId, String targetName) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('development_reports')
          .where('sessionId', isEqualTo: widget.session.id)
          .where('targetId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Bu kişi için henüz bir rapor oluşturulmamış."),
            ),
          );
        }
        return;
      }

      final report = DevelopmentReport.fromMap({
        ...snap.docs.first.data(),
        'id': snap.docs.first.id,
      });

      await DevelopmentReportPdfHelper.generateAndPrint(report, targetName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Rapor hazırlanırken hata oluştu: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allTargets
        .where(
          (t) => t['name'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();

    bool isMobile = MediaQuery.of(context).size.width < 600;

    Widget content = Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 0,
            vertical: isMobile ? 8 : 12,
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Kişi Ara...",
              hintStyle: TextStyle(color: Colors.indigo.withOpacity(0.4)),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.indigo.withOpacity(0.6),
              ),
              filled: true,
              fillColor: Colors.indigo.withOpacity(0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.indigo.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.indigo.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.all(16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(strokeWidth: 2))
              : filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Kişi bulunamadı.",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: isMobile
                      ? EdgeInsets.fromLTRB(16, 0, 16, 16)
                      : EdgeInsets.only(bottom: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final target = filtered[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.indigo.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade50,
                            child: Text(
                              target['name'][0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            target['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF334155),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionIcon(
                                icon: Icons.picture_as_pdf_rounded,
                                color: Colors.red.shade400,
                                tooltip: 'PDF İndir',
                                onPressed: () => _exportIndividualPdf(
                                  target['id'],
                                  target['name'],
                                ),
                              ),
                              SizedBox(width: 8),
                              _buildActionIcon(
                                icon: Icons.table_chart_rounded,
                                color: Colors.green.shade500,
                                tooltip: 'Excel İndir',
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Excel yakında eklenecek"),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Bireysel Rapor Al"),
          backgroundColor: Colors.white,
          foregroundColor: Colors.indigo,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: content,
      );
    }

    return AlertDialog(
      title: Text("Bireysel Rapor Al", style: TextStyle(color: Colors.indigo)),
      content: SizedBox(width: 450, height: 600, child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Kapat"),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}

class _BulkExportDialog extends StatefulWidget {
  final DevelopmentReportSession session;
  const _BulkExportDialog({required this.session});

  @override
  __BulkExportDialogState createState() => __BulkExportDialogState();
}

class __BulkExportDialogState extends State<_BulkExportDialog> {
  List<Map<String, dynamic>> _allTargets = [];
  Set<String> _selectedTargetIds = {};
  bool _isLoading = true;

  // Filters
  String? _selectedFilter1; // Could be Grade or Branch
  String? _selectedFilter2; // Could be Section or Title

  Set<String> _availableFilter1s = {};
  Set<String> _availableFilter2s = {};

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    try {
      final List<Map<String, dynamic>> loaded = [];
      final collectionName = widget.session.targetGroup == 'student'
          ? 'students'
          : 'users';

      // Chunking the targetIds
      final targetIds = widget.session.targetUserIds;
      for (var i = 0; i < targetIds.length; i += 10) {
        final chunk = targetIds.skip(i).take(10).toList();
        final snap = await FirebaseFirestore.instance
            .collection(collectionName)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in snap.docs) {
          final data = doc.data();
          String name =
              data['fullName'] ??
              data['name'] ??
              data['firstName'] ??
              'İsimsiz';
          if (data['lastName'] != null) name += ' ${data['lastName']}';

          String filter1 = '';
          String filter2 = '';

          if (widget.session.targetGroup == 'student') {
            filter1 = data['classLevel']?.toString() ?? 'Belirsiz';
            filter2 =
                data['branch']?.toString() ??
                data['section']?.toString() ??
                'Belirsiz';
          } else if (widget.session.targetGroup == 'teacher') {
            filter1 = data['branch']?.toString() ?? 'Belirsiz Branş';
            // no filter2 usually
          } else {
            filter1 = data['role']?.toString() ?? 'Belirsiz Ünvan';
          }

          loaded.add({
            'id': doc.id,
            'name': name,
            'filter1': filter1,
            'filter2': filter2,
          });

          if (filter1.isNotEmpty) _availableFilter1s.add(filter1);
          if (filter2.isNotEmpty) _availableFilter2s.add(filter2);
        }
      }

      loaded.sort(
        (a, b) => a['name'].toString().compareTo(b['name'].toString()),
      );

      if (mounted) {
        setState(() {
          _allTargets = loaded;
          _selectedTargetIds = loaded.map((e) => e['id'] as String).toSet();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Kişiler yüklenirken hata oluştu: $e")),
        );
      }
    }
  }

  Future<void> _exportBulkPdf() async {
    if (_selectedTargetIds.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('development_reports')
          .where('sessionId', isEqualTo: widget.session.id)
          .where(
            'targetId',
            whereIn: _selectedTargetIds.toList().take(30).toList(),
          )
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Seçili kişiler için henüz rapor oluşturulmamış."),
            ),
          );
        }
        return;
      }

      final reports = snap.docs
          .map((d) => DevelopmentReport.fromMap({...d.data(), 'id': d.id}))
          .toList();

      final Map<String, String> names = {
        for (var t in _allTargets) t['id']: t['name'],
      };

      await DevelopmentReportPdfHelper.generateBulkPdf(reports, names);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Toplu rapor hazırlanırken hata oluştu: $e")),
        );
      }
    }
  }

  void _toggleAll(bool select, List<Map<String, dynamic>> currentList) {
    if (select) {
      _selectedTargetIds.addAll(currentList.map((e) => e['id'] as String));
    } else {
      _selectedTargetIds.removeAll(currentList.map((e) => e['id'] as String));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Apply filters
    List<Map<String, dynamic>> filtered = _allTargets;
    if (_selectedFilter1 != null && _selectedFilter1!.isNotEmpty) {
      filtered = filtered
          .where((t) => t['filter1'] == _selectedFilter1)
          .toList();
    }
    if (_selectedFilter2 != null && _selectedFilter2!.isNotEmpty) {
      filtered = filtered
          .where((t) => t['filter2'] == _selectedFilter2)
          .toList();
    }

    bool allSelected =
        filtered.isNotEmpty &&
        filtered.every((t) => _selectedTargetIds.contains(t['id']));

    bool isMobile = MediaQuery.of(context).size.width < 600;

    Widget content = Column(
      children: [
        // Filters Row
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 0,
            vertical: 8,
          ),
          child: Row(
            children: [
              if (_availableFilter1s.isNotEmpty)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: widget.session.targetGroup == 'student'
                          ? 'Sınıf Seviyesi'
                          : widget.session.targetGroup == 'teacher'
                          ? 'Branş'
                          : 'Ünvan',
                      labelStyle: TextStyle(
                        color: Colors.indigo.shade400,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.indigo.withOpacity(0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.indigo.withOpacity(0.1),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    value: _selectedFilter1,
                    items: [
                      DropdownMenuItem(value: null, child: Text("Tümü")),
                      ..._availableFilter1s
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                    ],
                    onChanged: (val) => setState(() => _selectedFilter1 = val),
                  ),
                ),
              if (_availableFilter1s.isNotEmpty &&
                  _availableFilter2s.isNotEmpty &&
                  widget.session.targetGroup == 'student')
                SizedBox(width: 12),
              if (_availableFilter2s.isNotEmpty &&
                  widget.session.targetGroup == 'student')
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Şube',
                      labelStyle: TextStyle(
                        color: Colors.indigo.shade400,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.indigo.withOpacity(0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.indigo.withOpacity(0.1),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    value: _selectedFilter2,
                    items: [
                      DropdownMenuItem(value: null, child: Text("Tümü")),
                      ..._availableFilter2s
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                    ],
                    onChanged: (val) => setState(() => _selectedFilter2 = val),
                  ),
                ),
            ],
          ),
        ),
        // Selection Info
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 0,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${filtered.length} Kişi Listeleniyor",
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton.icon(
                icon: Icon(
                  allSelected ? Icons.deselect : Icons.select_all,
                  size: 18,
                ),
                label: Text(allSelected ? "Tümünü Kaldır" : "Tümünü Seç"),
                onPressed: () => _toggleAll(!allSelected, filtered),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  textStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.indigo.withOpacity(0.1)),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView.builder(
                  padding: isMobile
                      ? EdgeInsets.symmetric(horizontal: 16)
                      : null,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final target = filtered[index];
                    final isSelected = _selectedTargetIds.contains(
                      target['id'],
                    );
                    String subtitle = '';
                    if (target['filter1'] != 'Belirsiz')
                      subtitle += target['filter1'];
                    if (target['filter2'] != 'Belirsiz' &&
                        target['filter2'].toString().isNotEmpty) {
                      subtitle += ' - ' + target['filter2'];
                    }

                    return Container(
                      margin: EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo.withOpacity(0.04)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.indigo.withOpacity(0.2)
                              : Colors.transparent,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true)
                              _selectedTargetIds.add(target['id']);
                            else
                              _selectedTargetIds.remove(target['id']);
                          });
                        },
                        activeColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          target['name'],
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 14,
                            color: isSelected
                                ? Colors.indigo
                                : Color(0xFF334155),
                          ),
                        ),
                        subtitle: subtitle.isNotEmpty
                            ? Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              )
                            : null,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    );
                  },
                ),
        ),
        if (isMobile)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.picture_as_pdf_rounded, size: 20),
                    label: Text("PDF"),
                    onPressed: _selectedTargetIds.isEmpty
                        ? null
                        : _exportBulkPdf,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.table_chart_rounded, size: 20),
                    label: Text("Excel"),
                    onPressed: _selectedTargetIds.isEmpty
                        ? null
                        : _exportBulkPdf,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            "Toplu Rapor Al",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.indigo,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: content,
      );
    }

    return AlertDialog(
      title: Text(
        "Toplu Rapor Al",
        style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
      ),
      content: Container(width: 600, height: 700, child: content),
      actionsPadding: EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Kapat", style: TextStyle(color: Colors.grey.shade600)),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.picture_as_pdf_rounded),
          label: Text("PDF Olarak Al"),
          onPressed: _selectedTargetIds.isEmpty ? null : _exportBulkPdf,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.table_chart_rounded),
          label: Text("Excel Olarak Al"),
          onPressed: _selectedTargetIds.isEmpty ? null : _exportBulkPdf,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}

Widget _buildActionIcon({
  required IconData icon,
  required Color color,
  required String tooltip,
  required VoidCallback onPressed,
}) {
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    ),
  );
}
