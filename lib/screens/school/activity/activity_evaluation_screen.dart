import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/activity/activity_model.dart';
import '../../../../models/survey_model.dart';
import '../../../../services/activity_service.dart';

class ActivityEvaluationScreen extends StatefulWidget {
  final ActivityObservation activity;
  final String studentId;
  final String studentName;

  const ActivityEvaluationScreen({
    Key? key,
    required this.activity,
    required this.studentId,
    required this.studentName,
  }) : super(key: key);

  @override
  State<ActivityEvaluationScreen> createState() =>
      _ActivityEvaluationScreenState();
}

class _ActivityEvaluationScreenState extends State<ActivityEvaluationScreen> {
  final ActivityService _activityService = ActivityService();
  final _formKey = GlobalKey<FormState>();

  // Responses: questionId -> value
  final Map<String, dynamic> _responses = {};

  bool _isLoading = false;
  bool _isAlreadyEvaluated = false;

  @override
  void initState() {
    super.initState();
    _checkExistingEvaluation();
  }

  Future<void> _checkExistingEvaluation() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final hasEval = await _activityService.hasEvaluated(
      widget.activity.id,
      widget.studentId,
      userId,
    );

    if (hasEval) {
      if (mounted) {
        setState(() => _isAlreadyEvaluated = true);
        // Ideally load the answers to show them, but for now just blockade
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.studentName} Değerlendirmesi'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: _isAlreadyEvaluated
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Bu öğrenci için değerlendirme yaptınız.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Geri Dön'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.activity.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Lütfen aşağıdaki soruları cevaplayınız.'),
                    const Divider(height: 32),

                    ...widget.activity.questions
                        .map((q) => _buildQuestionItem(q))
                        .toList(),

                    const SizedBox(height: 32),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isLoading ? null : _submitEvaluation,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Değerlendirmeyi Kaydet',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildQuestionItem(SurveyQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: q.text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              children: [
                if (q.isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildInputForType(q),
        ],
      ),
    );
  }

  Widget _buildInputForType(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.text:
      case SurveyQuestionType.longText:
        return TextFormField(
          maxLines: q.type == SurveyQuestionType.longText ? 3 : 1,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          validator: (v) {
            if (q.isRequired && (v == null || v.isEmpty))
              return 'Bu alan zorunludur';
            return null;
          },
          onSaved: (v) => _responses[q.id] = v,
          onChanged: (v) => _responses[q.id] = v, // update live
        );

      case SurveyQuestionType.singleChoice: // Used as Yes/No usually
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: (q.options.isNotEmpty ? q.options : ['Evet', 'Hayır'])
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          validator: (v) => q.isRequired && v == null ? 'Seçim yapınız' : null,
          onChanged: (v) => setState(() => _responses[q.id] = v),
        );

      case SurveyQuestionType.rating:
        // 1-5 Star rating
        double currentVal = (_responses[q.id] as num?)?.toDouble() ?? 0;
        return Row(
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(
                index < currentVal ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 32,
              ),
              onPressed: () {
                setState(() {
                  _responses[q.id] = index + 1;
                });
              },
            );
          }),
        );

      default:
        return const Text('Desteklenmeyen soru tipi');
    }
  }

  Future<void> _submitEvaluation() async {
    if (!_formKey.currentState!.validate()) return;

    // Manual check for ratings/custom fields not covered by FormField validators usually
    for (var q in widget.activity.questions) {
      if (q.isRequired && _responses[q.id] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${q.text} sorusunu cevaplayınız')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      final userName = doc.exists
          ? (doc.data()?['fullName'] ?? 'Öğretmen')
          : 'Bilinmiyor';

      final evaluation = ActivityEvaluation(
        id: '', // Generated
        activityId: widget.activity.id,
        studentId: widget.studentId,
        evaluatorId: user.uid,
        evaluatorName: userName,
        createdAt: DateTime.now(),
        responses: _responses,
      );

      await _activityService.submitEvaluation(evaluation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Değerlendirme kaydedildi!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
