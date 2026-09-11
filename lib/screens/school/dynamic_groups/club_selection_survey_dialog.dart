import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/school/dynamic_course_group_model.dart';
import '../../../services/term_service.dart';

const Color _clubColor = Color(0xFF059669);
const Color _clubLightColor = Color(0xFFD1FAE5);

/// Öğrenci veya İdareci için Kulüp Tercih Anketi Dialogu
class ClubSelectionSurveyDialog extends StatefulWidget {
  final DynamicCourseGroup group;
  final String studentId;
  final String studentName;
  final String institutionId;
  final String schoolTypeId;

  const ClubSelectionSurveyDialog({
    super.key,
    required this.group,
    required this.studentId,
    required this.studentName,
    required this.institutionId,
    required this.schoolTypeId,
  });

  @override
  State<ClubSelectionSurveyDialog> createState() => _ClubSelectionSurveyDialogState();
}

class _ClubSelectionSurveyDialogState extends State<ClubSelectionSurveyDialog> {
  String? _firstChoiceSubId;
  String? _secondChoiceSubId;
  String? _thirdChoiceSubId;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingPreferences();
  }

  Future<void> _loadExistingPreferences() async {
    try {
      final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final docId = '${termId}_${widget.group.id}_${widget.studentId}';
      final doc = await FirebaseFirestore.instance.collection('clubSurveys').doc(docId).get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            _firstChoiceSubId = data['firstChoiceSubId']?.toString();
            _secondChoiceSubId = data['secondChoiceSubId']?.toString();
            _thirdChoiceSubId = data['thirdChoiceSubId']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePreferences() async {
    if (_firstChoiceSubId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en azından 1. Tercihinizi belirleyin.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final docId = '${termId}_${widget.group.id}_${widget.studentId}';

      await FirebaseFirestore.instance.collection('clubSurveys').doc(docId).set({
        'id': docId,
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'termId': termId,
        'groupId': widget.group.id,
        'groupName': widget.group.name,
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'firstChoiceSubId': _firstChoiceSubId,
        'secondChoiceSubId': _secondChoiceSubId,
        'thirdChoiceSubId': _thirdChoiceSubId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kulüp tercihleriniz kaydedildi!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubs = widget.group.subGroups;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _clubLightColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.how_to_vote_rounded, color: _clubColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kulüp Tercih Anketi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(widget.studentName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lütfen katılmak istediğiniz kulüpleri öncelik sırasına göre seçiniz:',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),

                    // 1. Tercih
                    _buildChoiceDropdown(
                      label: '1. Tercih (Öncelikli)',
                      color: _clubColor,
                      value: _firstChoiceSubId,
                      clubs: clubs,
                      onChanged: (val) => setState(() => _firstChoiceSubId = val),
                    ),
                    const SizedBox(height: 12),

                    // 2. Tercih
                    _buildChoiceDropdown(
                      label: '2. Tercih',
                      color: Colors.blue.shade700,
                      value: _secondChoiceSubId,
                      clubs: clubs,
                      onChanged: (val) => setState(() => _secondChoiceSubId = val),
                    ),
                    const SizedBox(height: 12),

                    // 3. Tercih
                    _buildChoiceDropdown(
                      label: '3. Tercih (Yedek)',
                      color: Colors.orange.shade700,
                      value: _thirdChoiceSubId,
                      clubs: clubs,
                      onChanged: (val) => setState(() => _thirdChoiceSubId = val),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _clubColor),
          onPressed: _saving ? null : _savePreferences,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Tercihleri Kaydet'),
        ),
      ],
    );
  }

  Widget _buildChoiceDropdown({
    required String label,
    required Color color,
    required String? value,
    required List<DynamicSubGroup> clubs,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        prefixIcon: Icon(Icons.sports_soccer_outlined, size: 20, color: color),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('- Tercih Seçin -')),
        ...clubs.map((c) {
          final room = c.classroomName.isNotEmpty ? ' (${c.classroomName})' : '';
          return DropdownMenuItem<String>(
            value: c.id,
            child: Text('${c.name}$room'),
          );
        }),
      ],
      onChanged: onChanged,
    );
  }
}
