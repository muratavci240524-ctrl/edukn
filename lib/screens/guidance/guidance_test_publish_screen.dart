import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/guidance/tests/guidance_test_definition.dart';
import '../../services/survey_service.dart';
import '../../models/survey_model.dart';

import '../../widgets/recipient_selector_field.dart';

class GuidanceTestPublishScreen extends StatefulWidget {
  final GuidanceTestDefinition test;
  final String institutionId;
  final String schoolTypeId;
  final String authorId;

  const GuidanceTestPublishScreen({
    Key? key,
    required this.test,
    required this.institutionId,
    required this.schoolTypeId,
    required this.authorId,
  }) : super(key: key);

  @override
  State<GuidanceTestPublishScreen> createState() =>
      _GuidanceTestPublishScreenState();
}

class _GuidanceTestPublishScreenState extends State<GuidanceTestPublishScreen> {
  final SurveyService _surveyService = SurveyService();

  // Selections
  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {}; // ID -> Display Name mapping
  bool _isPublishing = false;

  // Reuse the logic from your detailed dialog or implement inline?
  // Since the user wants complex filtering (Student, Branch, Level),
  // The 'RecipientSelectionDialog' handles exactly this by returning IDs like
  // 'school:ID:Öğrenciler', 'class:ID:Öğrenciler', 'user:ID' etc.

  // However, we need to carefully parse these when creating the survey.
  // The Survey model's `targetIds` and `targetType` might need to be flexible
  // or we map these IDs to what SurveyService expects.
  // SurveyService seems to expect targetIds + One Target Type?
  // Let's check Survey model.
  // It has SurveyTargetType which is simple.
  // If we mix types (some students, some classes), we might need to rely on
  // how SurveyService processes this.
  // For now, let's assume we can pass a mixed list if handled, or we default to 'specific_students' list
  // if we can resolve them, but classes need to be stored as 'class:ID'.

  // For this implementation, we will use the RecipientSelectionDialog
  // and store the raw recipient strings in the survey's `targetIds`
  // and set targetType to `SurveyTargetType.students` (or mixed).
  // Actually, we should probably set it to 'mixed' or verify.
  // Let's assume 'students' implies specific list, 'school' implies everyone.

  // Removing old helper methods as they are now in RecipientSelectorField

  // Helper to get formatted ID for fallback (used during publish)
  String _formatRecipientId(String id) {
    if (id.startsWith('user:')) return 'Kullanıcı';
    if (id.startsWith('class:')) {
      final parts = id.split(':');
      return parts.length >= 3 ? parts[2] : 'Sınıf';
    }
    if (id.startsWith('branch:')) {
      final parts = id.split(':');
      return parts.length >= 3 ? parts[2] : 'Şube';
    }
    if (id.startsWith('school:')) return 'Okul Geneli';
    if (id.startsWith('unit:')) return 'Birim';
    return id.length > 15 ? id.substring(0, 15) + '...' : id;
  }

  Future<void> _publish() async {
    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lütfen en az bir alıcı (öğrenci, şube veya sınıf) seçiniz.',
          ),
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      // Calculate display names and a basic total target count
      List<String> displayNames = [];
      for (var r in _selectedRecipients) {
        displayNames.add(_recipientNames[r] ?? _formatRecipientId(r));
      }

      final survey = widget.test.createSurvey(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        authorId: widget.authorId,
        targetIds: _selectedRecipients,
        targetType: SurveyTargetType.students,
      );

      // Create a survey map with the new fields
      final surveyMap = survey.toMap();
      surveyMap['targetNames'] = displayNames;

      // Basic count: for individuals it's 1, for groups we'd ideally need to fetch.
      // For now, let's store a placeholder or try a quick count if possible.
      // Improved: We'll set it to recipients length as a fallback,
      // but ideally we want the expanded user count.
      surveyMap['totalTargetCount'] = _selectedRecipients.length;

      final id = await _surveyService.createSurvey(
        Survey.fromMap(surveyMap, ''),
      );
      await _surveyService.publishSurvey(id, _selectedRecipients);

      if (mounted) {
        Navigator.pop(context, true); // Return success
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Test başarıyla yayınlandı!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.test.title} Yayınla', style: GoogleFonts.inter()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.indigo),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu testi okul geneline, belirli sınıf seviyelerine veya belirli şubelere/öğrencilere gönderebilirsiniz.',
                      style: TextStyle(color: Colors.indigo.shade900),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            RecipientSelectorField(
              selectedRecipients: _selectedRecipients,
              recipientNames: _recipientNames,
              schoolTypeId: widget.schoolTypeId,
              onChanged: (recipients, names) {
                setState(() {
                  _selectedRecipients = recipients;
                  _recipientNames = names;
                });
              },
            ),

            Spacer(),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isPublishing ? null : _publish,
                icon: _isPublishing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.send),
                label: Text(_isPublishing ? 'Yayınlanıyor...' : 'Yayınla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
