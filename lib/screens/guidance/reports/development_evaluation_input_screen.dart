import 'package:flutter/material.dart';
import '../../../models/guidance/development_report/development_report_model.dart';
import '../../../models/guidance/development_report/development_evaluation_model.dart';
import '../../../models/guidance/development_report/development_criterion_model.dart';
import '../../../services/development_report_service.dart';
import '../../../services/user_permission_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DevelopmentEvaluationInputScreen extends StatefulWidget {
  final DevelopmentReport report;
  final String evaluatorRole; // 'teacher', 'guidance', 'student', 'parent'
  final VoidCallback? onEvaluationSaved;

  const DevelopmentEvaluationInputScreen({
    Key? key,
    required this.report,
    required this.evaluatorRole,
    this.onEvaluationSaved,
  }) : super(key: key);

  @override
  _DevelopmentEvaluationInputScreenState createState() =>
      _DevelopmentEvaluationInputScreenState();
}

class _DevelopmentEvaluationInputScreenState
    extends State<DevelopmentEvaluationInputScreen> {
  final DevelopmentReportService _service = DevelopmentReportService();
  final _formKey = GlobalKey<FormState>();

  List<DevelopmentCriterion> _criteria = [];
  Map<String, double> _scores = {};
  Map<String, String> _comments = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 1. Fetch Criteria
    final criteriaStream = _service.getCriteria(widget.report.institutionId);
    final criteria = await criteriaStream.first;

    // 2. Fetch User Data for Name
    final userData = await UserPermissionService.loadUserData();
    final displayName = UserPermissionService.getUserDisplayName(userData);

    // 3. Fetch Existing Evaluation (if any)
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final allEvaluations = await _service.getReportEvaluations(
      widget.report.id,
    );
    final myEvaluation = allEvaluations.firstWhere(
      (e) => e.evaluatorId == userId,
      orElse: () => DevelopmentEvaluation(
        id: '',
        institutionId: widget.report.institutionId,
        reportId: widget.report.id,
        evaluatorId: userId,
        evaluatorName: displayName,
        evaluatorRole: widget.evaluatorRole,
        createdAt: DateTime.now(),
      ),
    );

    if (mounted) {
      setState(() {
        _criteria = criteria;
        _scores = Map<String, double>.from(myEvaluation.scores);
        _comments = Map<String, String>.from(myEvaluation.comments);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveEvaluation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception("User not logged in");

      // Fetch latest name just in case
      final userData = UserPermissionService.getCachedUserData();
      final displayName = UserPermissionService.getUserDisplayName(userData);

      final eval = DevelopmentEvaluation(
        id: '',
        institutionId: widget.report.institutionId,
        reportId: widget.report.id,
        evaluatorId: userId,
        evaluatorName: displayName,
        evaluatorRole: widget.evaluatorRole,
        scores: _scores,
        comments: _comments,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final deterministicId = "${widget.report.id}_$userId";

      final finalEval = DevelopmentEvaluation(
        id: deterministicId,
        institutionId: eval.institutionId,
        reportId: eval.reportId,
        evaluatorId: eval.evaluatorId,
        evaluatorName: eval.evaluatorName,
        evaluatorRole: eval.evaluatorRole,
        scores: eval.scores,
        comments: eval.comments,
        createdAt: eval.createdAt,
        updatedAt: eval.updatedAt,
      );

      await _service.submitEvaluation(finalEval);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Değerlendirme kaydedildi.')));
        if (widget.onEvaluationSaved != null) {
          widget.onEvaluationSaved!();
        }
        if (MediaQuery.of(context).size.width < 600) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      print(e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Değerlendirme Girişi"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo,
        elevation: 1,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: _criteria.length + 1,
                itemBuilder: (context, index) {
                  if (index == _criteria.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveEvaluation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text("Kaydet ve Tamamla"),
                      ),
                    );
                  }

                  final criterion = _criteria[index];
                  // Section Header if category changes
                  bool showHeader =
                      index == 0 ||
                      _criteria[index - 1].category != criterion.category;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader) ...[
                        SizedBox(height: 16),
                        Text(
                          criterion.category.toUpperCase(),
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Divider(color: Colors.indigo.shade100, thickness: 2),
                        SizedBox(height: 8),
                      ],
                      Card(
                        margin: EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                criterion.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              if (criterion.description.isNotEmpty)
                                Text(
                                  criterion.description,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              SizedBox(height: 12),
                              _buildInputForType(criterion),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildInputForType(DevelopmentCriterion criterion) {
    double currentVal = _scores[criterion.id] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Text(
              "Puan: ${currentVal.toInt()}",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            Expanded(
              child: Slider(
                value: currentVal,
                min: 0,
                max: 5,
                divisions: 5,
                label: currentVal.toInt().toString(),
                activeColor: Colors.indigo,
                onChanged: (val) => setState(() => _scores[criterion.id] = val),
              ),
            ),
          ],
        ),
        TextFormField(
          initialValue: _comments[criterion.id],
          onChanged: (val) => _comments[criterion.id] = val,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            hintText: "Yorumunuz (İsteğe bağlı)",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.indigo.shade300, width: 1.5),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}
