import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/survey_model.dart';
import '../../../services/survey_service.dart';
import '../../guidance/execution/burdon_test_execution_screen.dart';

class SurveyResponseScreen extends StatefulWidget {
  // Pass either surveyId (to fetch from DB) OR survey (for preview)
  final String? surveyId;
  final Survey? survey;

  const SurveyResponseScreen({Key? key, this.surveyId, this.survey})
    : super(key: key);

  @override
  State<SurveyResponseScreen> createState() => _SurveyResponseScreenState();
}

class _SurveyResponseScreenState extends State<SurveyResponseScreen> {
  final SurveyService _surveyService = SurveyService();
  bool _isLoading = true;
  bool _isSubmitting = false;
  Survey? _survey;
  Map<String, dynamic> _answers = {};

  int _currentStep = 0;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _invalidQuestionIds = {};

  @override
  void initState() {
    super.initState();
    _loadSurvey();
  }

  Future<void> _loadSurvey() async {
    // PREVIEW MODE
    if (widget.survey != null) {
      setState(() {
        _survey = widget.survey;
        _isLoading = false;
      });
      return;
    }

    // EXISTING FETCH MODE
    if (widget.surveyId == null) {
      setState(() => _isLoading = false);
      return;
    }

    print('📝 SurveyResponseScreen: Loading survey ${widget.surveyId}');

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No current user');
        setState(() => _isLoading = false);
        return;
      }

      print('📝 Fetching survey and user response...');
      final results =
          await Future.wait([
            _surveyService.getSurvey(widget.surveyId!),
            _surveyService.getUserResponse(widget.surveyId!, currentUser.uid),
          ]).timeout(
            Duration(seconds: 10),
            onTimeout: () {
              print('⚠️ Survey load timed out');
              return [null, null];
            },
          );

      final survey = results[0] as Survey?;
      final existingResponse = results[1] as Map<String, dynamic>?;

      print('✅ Survey loaded: ${survey != null}');
      print('✅ Existing response: ${existingResponse != null}');

      if (mounted) {
        setState(() {
          _survey = survey;
          if (existingResponse != null && existingResponse['answers'] != null) {
            _answers = Map<String, dynamic>.from(existingResponse['answers']);
          }
          _isLoading = false;
        });

        if (existingResponse != null) {
          _showAlreadyRespondedDialog();
        }
      }
    } catch (e, stackTrace) {
      print('❌ SurveyResponseScreen error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAlreadyRespondedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Zaten Yanıtladınız'),
        content: Text(
          'Bu anketi daha önce doldurdunuz. Yanıtlarınızı düzenlemek ister misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Hayır, Çık'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: Text('Evet, Düzenle'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitSurvey() async {
    if (_survey == null) return;

    // PREVIEW MODE HANDLE
    if (widget.surveyId == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Önizleme Modu'),
          content: Text('Bu bir önizlemedir. Cevaplar kaydedilmez.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Close screen
              },
              child: Text('Tamam, Çık'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _surveyService.submitResponse(widget.surveyId!, _answers);
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Teşekkürler'),
            content: Text('Anket yanıtlarınız başarıyla gönderildi.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gönderim hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _validateCurrentSection() {
    if (_survey == null) return false;
    final section = _survey!.sections[_currentStep];
    _invalidQuestionIds.clear();
    int? firstInvalidIndex;

    for (int i = 0; i < section.questions.length; i++) {
      final question = section.questions[i];
      if (question.isRequired) {
        final answer = _answers[question.id];
        bool isMissing = false;
        if (answer == null) {
          isMissing = true;
        } else if (answer is String && answer.isEmpty) {
          isMissing = true;
        } else if (answer is List && answer.isEmpty) {
          isMissing = true;
        } else if (answer is Map && answer.isEmpty) {
          isMissing = true;
        }

        if (isMissing) {
          _invalidQuestionIds.add(question.id);
          firstInvalidIndex ??= i;
        }
      }
    }

    if (_invalidQuestionIds.isNotEmpty) {
      setState(() {}); // Trigger rebuild to show red borders
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lütfen eksik soruları doldurunuz.'),
          backgroundColor: Colors.red,
        ),
      );

      // Scroll to first invalid item
      if (firstInvalidIndex != null) {
        // Adjust offset for description and section title
        int offsetItems = 0;
        if (_currentStep == 0 && _survey!.description.isNotEmpty) offsetItems++;
        if (_survey!.sections.length > 1 || section.title.isNotEmpty) {
          offsetItems++;
        }

        final targetIndex = firstInvalidIndex + offsetItems;
        // Estimate position (roughly 140px per question card + margins)
        // This is a heuristic since ListView.builder doesn't know exact offsets
        _scrollController.animateTo(
          targetIndex * 150.0,
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
      return false;
    }
    return true;
  }

  void _nextStep() {
    if (_validateCurrentSection()) {
      setState(() {
        if (_currentStep < _survey!.sections.length - 1) {
          _currentStep++;
        } else {
          _submitSurvey();
        }
      });
    }
  }

  void _prevStep() {
    setState(() {
      if (_currentStep > 0) _currentStep--;
    });
  }

  void _jumpToStep(int step) {
    // Only allow jumping backward or to current+1 if valid
    if (step < _currentStep) {
      setState(() => _currentStep = step);
    } else if (step == _currentStep + 1) {
      _nextStep();
    }
    // We don't allow jumping far ahead without validation
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Anket Yükleniyor...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_survey == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Hata')),
        body: Center(child: Text('Anket bulunamadı veya silinmiş.')),
      );
    }

    // SPECIAL HANDLING FOR BURDON ATTENTION TEST
    if (_survey?.guidanceTemplateId == 'burdon_v1') {
      return BurdonTestExecutionScreen(
        survey: _survey!,
        surveyId: widget.surveyId,
      );
    }

    final isLastStep = _currentStep == _survey!.sections.length - 1;
    final currentSection = _survey!.sections[_currentStep];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _survey!.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // STEP INDICATOR
            if (_survey!.sections.length > 1)
              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_survey!.sections.length, (index) {
                    final isActive = index == _currentStep;
                    final isCompleted = index < _currentStep;

                    return GestureDetector(
                      onTap: () => _jumpToStep(index),
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 8),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? Colors.indigo
                              : (isCompleted ? Colors.green : Colors.grey[300]),
                          border: isActive
                              ? null
                              : Border.all(color: Colors.grey[300]!),
                        ),
                        alignment: Alignment.center,
                        child: isCompleted
                            ? Icon(Icons.check, size: 16, color: Colors.white)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    );
                  }),
                ),
              ),

            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 800),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(24),
                    itemCount:
                        (currentSection.questions.length) +
                        (_currentStep == 0 && _survey!.description.isNotEmpty
                            ? 1
                            : 0) +
                        (_survey!.sections.length > 1 ||
                                currentSection.title.isNotEmpty
                            ? 1
                            : 0) +
                        1, // Padding at bottom
                    itemBuilder: (context, index) {
                      int offset = 0;

                      // Description
                      if (_currentStep == 0 &&
                          _survey!.description.isNotEmpty) {
                        if (index == 0) {
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            margin: EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              _survey!.description,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                                height: 1.5,
                              ),
                            ),
                          );
                        }
                        offset++;
                      }

                      // Section Title
                      if (_survey!.sections.length > 1 ||
                          currentSection.title.isNotEmpty) {
                        if (index == offset) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              currentSection.title,
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          );
                        }
                        offset++;
                      }

                      // Questions
                      final qIndex = index - offset;
                      if (qIndex >= 0 &&
                          qIndex < currentSection.questions.length) {
                        final q = currentSection.questions[qIndex];
                        return _buildQuestionItem(q, qIndex + 1);
                      }

                      // Bottom space
                      return SizedBox(height: 100);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: EdgeInsets.all(16),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: _survey!.sections.length == 1
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (_survey!.sections.length > 1)
                if (_currentStep > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: Icon(Icons.arrow_back),
                    label: Text('Geri'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  SizedBox(width: 80), // Spacer

              ElevatedButton(
                onPressed:
                    (_isSubmitting || _survey!.status == SurveyStatus.closed)
                    ? null
                    : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLastStep ? Colors.green : Colors.indigo,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        children: [
                          Text(isLastStep ? 'GÖNDER' : 'İLERİ'),
                          if (!isLastStep) ...[
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionItem(SurveyQuestion q, int number) {
    final bool isInvalid = _invalidQuestionIds.contains(q.id);
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInvalid ? Colors.red.shade400 : Colors.grey.shade200,
          width: isInvalid ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isInvalid
                ? Colors.red.withOpacity(0.05)
                : Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: '$number. ',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
              children: [
                TextSpan(
                  text: q.text,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                if (q.isRequired)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16),
          _buildInput(q),
        ],
      ),
    );
  }

  Widget _buildInput(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.text:
        return TextField(
          decoration: InputDecoration(
            hintText: 'Yanıtınız...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (val) => _answers[q.id] = val,
        );
      case SurveyQuestionType.longText:
        return TextField(
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Yanıtınız...',
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => _answers[q.id] = val,
        );
      case SurveyQuestionType.singleChoice:
        final bool isShortOptions = q.options.every((opt) => opt.length <= 2);
        if (isShortOptions) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: q.options.map((opt) {
              final isSelected = _answers[q.id] == opt;
              return InkWell(
                onTap: () => setState(() => _answers[q.id] = opt),
                child: Column(
                  children: [
                    Text(
                      opt,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.indigo : Colors.grey,
                      ),
                    ),
                    Radio<String>(
                      value: opt,
                      groupValue: _answers[q.id],
                      onChanged: (val) => setState(() => _answers[q.id] = val),
                      activeColor: Colors.indigo,
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        }
        return Column(
          children: q.options.map((opt) {
            return RadioListTile<String>(
              title: Text(opt),
              value: opt,
              groupValue: _answers[q.id],
              onChanged: (val) => setState(() => _answers[q.id] = val),
              dense: true,
              contentPadding: EdgeInsets.zero,
            );
          }).toList(),
        );
      case SurveyQuestionType.multipleChoice:
        final List<String> currentSelections = List<String>.from(
          _answers[q.id] ?? [],
        );
        return Column(
          children: q.options.map((opt) {
            final isSelected = currentSelections.contains(opt);
            return CheckboxListTile(
              title: Text(opt),
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    currentSelections.add(opt);
                  } else {
                    currentSelections.remove(opt);
                  }
                  _answers[q.id] = currentSelections;
                });
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            );
          }).toList(),
        );
      case SurveyQuestionType.rating:
        int currentRating = _answers[q.id] ?? 0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final rating = index + 1;
            return IconButton(
              icon: Icon(
                rating <= currentRating ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 32,
              ),
              onPressed: () => setState(() => _answers[q.id] = rating),
            );
          }),
        );
      case SurveyQuestionType.date:
        // Simple date picker placeholder for now
        return OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(
                () => _answers[q.id] = picked.toIso8601String().split('T')[0],
              );
            }
          },
          icon: Icon(Icons.calendar_today),
          label: Text(_answers[q.id] ?? 'Tarih Seçiniz'),
        );
      case SurveyQuestionType.ranking:
        // Advanced ranking with modern, premium UI
        // Safely convert from Firestore dynamic map to Map<String, int>
        final Map<String, int> currentRankings = {};
        final rawData = _answers[q.id];
        if (rawData != null && rawData is Map) {
          rawData.forEach((key, value) {
            if (value is int) {
              currentRankings[key.toString()] = value;
            } else if (value is num) {
              currentRankings[key.toString()] = value.toInt();
            }
          });
        }

        // Get all rankings across ALL questions to track global choice numbers
        final Map<String, int> allRankings = {};
        for (var section in _survey!.sections) {
          for (var question in section.questions) {
            if (question.type == SurveyQuestionType.ranking) {
              final rankings = _answers[question.id];
              if (rankings != null && rankings is Map) {
                rankings.forEach((key, value) {
                  if (value is int) {
                    allRankings[key.toString()] = value;
                  } else if (value is num) {
                    allRankings[key.toString()] = value.toInt();
                  }
                });
              }
            }
          }
        }

        final choicesInThisSubject = currentRankings.length;

        int subjectsWithChoices = 0;
        for (var section in _survey!.sections) {
          for (var question in section.questions) {
            if (question.type == SurveyQuestionType.ranking) {
              final rankings = _answers[question.id] as Map<String, int>?;
              if (rankings != null && rankings.isNotEmpty) {
                subjectsWithChoices++;
              }
            }
          }
        }

        final usedChoiceNumbers = allRankings.values.toSet();
        final totalChoicesMade = usedChoiceNumbers.length;

        final maxTotal = _survey!.maxTotalChoices ?? 999;
        final maxSubjects = _survey!.maxSubjects ?? 999;
        final maxPerSubject = _survey!.maxChoicesPerSubject ?? 999;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium info banner with gradient
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade50, Colors.blue.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.rule, color: Colors.white, size: 20),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Tercih Kuralları',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _buildRuleRow(
                    Icons.format_list_numbered,
                    'Toplam $maxTotal tercih',
                    'Yapılan: $totalChoicesMade',
                    totalChoicesMade,
                    maxTotal,
                  ),
                  SizedBox(height: 8),
                  _buildRuleRow(
                    Icons.school,
                    'En fazla $maxSubjects ders',
                    'Seçilen: $subjectsWithChoices',
                    subjectsWithChoices,
                    maxSubjects,
                  ),
                  SizedBox(height: 8),
                  _buildRuleRow(
                    Icons.bookmark,
                    'Ders başına $maxPerSubject tercih',
                    'Bu ders: $choicesInThisSubject',
                    choicesInThisSubject,
                    maxPerSubject,
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.amber.shade700,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tercih numaraları tüm dersler arasında devam eder',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            ...q.options.map((option) {
              final currentRank = currentRankings[option];

              List<int> availableChoices = [];
              for (int i = 1; i <= maxTotal; i++) {
                if (i == currentRank || !usedChoiceNumbers.contains(i)) {
                  availableChoices.add(i);
                }
              }

              final canAddChoice =
                  totalChoicesMade < maxTotal &&
                  choicesInThisSubject < maxPerSubject &&
                  (currentRank != null ||
                      subjectsWithChoices < maxSubjects ||
                      choicesInThisSubject > 0);

              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: currentRank != null
                      ? Colors.indigo.shade50
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: currentRank != null
                        ? Colors.indigo.shade300
                        : Colors.grey.shade300,
                    width: currentRank != null ? 2 : 1,
                  ),
                  boxShadow: [
                    if (currentRank != null)
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    // Choice number badge
                    if (currentRank != null)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.indigo, Colors.indigo.shade700],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigo.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '$currentRank',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.radio_button_unchecked,
                          color: Colors.grey.shade400,
                          size: 20,
                        ),
                      ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: currentRank != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: currentRank != null
                              ? Colors.indigo.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        value: currentRank,
                        decoration: InputDecoration(
                          labelText: 'Tercih Sırası',
                          labelStyle: TextStyle(fontSize: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          errorText: !canAddChoice && currentRank == null
                              ? 'Limit'
                              : null,
                        ),
                        items: [
                          DropdownMenuItem<int>(
                            value: null,
                            child: Text(
                              'Seçiniz',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          ...availableChoices.map((rank) {
                            return DropdownMenuItem<int>(
                              value: rank,
                              child: Text(
                                '$rank. Tercih',
                                style: TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: canAddChoice || currentRank != null
                            ? (val) {
                                setState(() {
                                  if (val == null) {
                                    currentRankings.remove(option);
                                  } else {
                                    currentRankings[option] = val;
                                  }
                                  _answers[q.id] = currentRankings;
                                });
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      default:
        return SizedBox();
    }
  }

  Widget _buildRuleRow(
    IconData icon,
    String title,
    String value,
    int current,
    int max,
  ) {
    final percentage = max > 0 ? (current / max) : 0.0;
    final color = percentage >= 1.0
        ? Colors.red
        : (percentage >= 0.7 ? Colors.orange : Colors.green);

    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.indigo.shade600),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
