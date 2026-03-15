import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../models/field_trip_model.dart';
import '../../../../models/survey_model.dart';
import '../../../../services/field_trip_service.dart';
import '../../../../services/survey_service.dart';
import 'field_trip_group_manager_screen.dart';

class FieldTripDetailScreen extends StatefulWidget {
  final FieldTrip trip;

  const FieldTripDetailScreen({Key? key, required this.trip}) : super(key: key);

  @override
  State<FieldTripDetailScreen> createState() => _FieldTripDetailScreenState();
}

class _FieldTripDetailScreenState extends State<FieldTripDetailScreen> {
  late FieldTrip _trip;
  final FieldTripService _service = FieldTripService();
  final SurveyService _surveyService = SurveyService();

  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _surveyResponses = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Reload trip to get latest manual statuses/groups
      final freshTrip = await _service.getFieldTrip(_trip.id);
      if (freshTrip != null) {
        _trip = freshTrip;
      }

      List<Map<String, dynamic>> loadedStudents = [];

      final ids = _trip.targetStudentIds;
      // Chunking for Firestore limits
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
        if (chunk.isEmpty) continue;

        final snapshot = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in snapshot.docs) {
          loadedStudents.add({'id': doc.id, ...doc.data()});
        }
      }

      loadedStudents.sort(
        (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''),
      );

      Map<String, Map<String, dynamic>> responsesMap = {};
      if (_trip.participationSurveyId != null) {
        final responses = await _surveyService.getSurveyResponses(
          _trip.participationSurveyId!,
        );
        for (var r in responses) {
          final userId = r['userId'] as String?;
          if (userId != null) {
            responsesMap[userId] = r;
          }
        }
      }

      if (mounted) {
        setState(() {
          _students = loadedStudents;
          _surveyResponses = responsesMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _toggleManualStatus(String studentId, String? status) async {
    final newMap = Map<String, String>.from(_trip.manualParticipationStatus);
    if (status == null) {
      newMap.remove(studentId);
    } else {
      newMap[studentId] = status;
    }

    final updatedTrip = FieldTrip(
      id: _trip.id,
      institutionId: _trip.institutionId,
      schoolTypeId: _trip.schoolTypeId,
      schoolTypeName: _trip.schoolTypeName,
      name: _trip.name,
      purpose: _trip.purpose,
      departureTime: _trip.departureTime,
      returnTime: _trip.returnTime,
      classLevel: _trip.classLevel,
      targetBranchIds: _trip.targetBranchIds,
      targetStudentIds: _trip.targetStudentIds,
      totalStudents: _trip.totalStudents,
      participationSurveyId: _trip.participationSurveyId,
      surveyPublishDate: _trip.surveyPublishDate,
      manualParticipationStatus: newMap,
      isPaid: _trip.isPaid,
      amount: _trip.amount,
      paymentStatus: _trip.paymentStatus,
      feedbackSurveyId: _trip.feedbackSurveyId,
      authorId: _trip.authorId,
      createdAt: _trip.createdAt,
      status: _trip.status,
      groups: _trip.groups,
    );

    setState(() => _trip = updatedTrip);

    try {
      await _service.updateFieldTrip(updatedTrip);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _togglePayment(String studentId, bool? value) async {
    if (value == null) return;

    final newMap = Map<String, bool>.from(_trip.paymentStatus);
    newMap[studentId] = value;

    setState(() {
      _trip = FieldTrip(
        id: _trip.id,
        institutionId: _trip.institutionId,
        schoolTypeId: _trip.schoolTypeId,
        schoolTypeName: _trip.schoolTypeName,
        name: _trip.name,
        purpose: _trip.purpose,
        departureTime: _trip.departureTime,
        returnTime: _trip.returnTime,
        classLevel: _trip.classLevel,
        targetBranchIds: _trip.targetBranchIds,
        targetStudentIds: _trip.targetStudentIds,
        totalStudents: _trip.totalStudents,
        participationSurveyId: _trip.participationSurveyId,
        surveyPublishDate: _trip.surveyPublishDate,
        manualParticipationStatus: _trip.manualParticipationStatus, // Preserve
        isPaid: _trip.isPaid,
        amount: _trip.amount,
        paymentStatus: newMap,
        feedbackSurveyId: _trip.feedbackSurveyId,
        authorId: _trip.authorId,
        createdAt: _trip.createdAt,
        status: _trip.status,
        groups: _trip.groups, // Preserve
      );
    });

    try {
      await _service.togglePaymentStatus(_trip.id, studentId, value);
    } catch (e) {
      _loadData();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem başarısız')));
    }
  }

  Future<void> _createFeedbackSurvey() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geri Dönüş Anketi'),
        content: const Text(
          'Gezi sonrası değerlendirme anketi oluşturulacak. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    try {
      final questions = [
        SurveyQuestion(
          id: '1',
          text: '${_trip.name} gezisini değerlendirin:',
          type: SurveyQuestionType.rating,
          isRequired: true,
          options: ['1', '2', '3', '4', '5'],
        ),
        SurveyQuestion(
          id: '2',
          text: 'Görüş ve Önerileriniz:',
          type: SurveyQuestionType.longText,
          isRequired: false,
        ),
      ];

      final survey = Survey(
        id: '',
        institutionId: _trip.institutionId,
        schoolTypeId: _trip.schoolTypeId,
        title: '${_trip.name} Değerlendirme',
        description: 'Lütfen birkaç dakika ayırıp değerlendirin.',
        authorId: _trip.authorId,
        createdAt: DateTime.now(),
        status: SurveyStatus.published,
        targetType: SurveyTargetType.students,
        targetIds: _trip.targetBranchIds,
        sections: [
          SurveySection(id: 'm', title: 'Genel', questions: questions),
        ],
      );

      final sid = await _surveyService.createSurvey(survey);
      await _surveyService.publishSurvey(sid, _trip.targetStudentIds);

      // Update Trip to save the feedbackSurveyId
      final updatedTrip = FieldTrip(
        id: _trip.id,
        institutionId: _trip.institutionId,
        schoolTypeId: _trip.schoolTypeId,
        schoolTypeName: _trip.schoolTypeName,
        name: _trip.name,
        purpose: _trip.purpose,
        departureTime: _trip.departureTime,
        returnTime: _trip.returnTime,
        classLevel: _trip.classLevel,
        targetBranchIds: _trip.targetBranchIds,
        targetStudentIds: _trip.targetStudentIds,
        totalStudents: _trip.totalStudents,
        participationSurveyId: _trip.participationSurveyId,
        surveyPublishDate: _trip.surveyPublishDate,
        manualParticipationStatus: _trip.manualParticipationStatus,
        isPaid: _trip.isPaid,
        amount: _trip.amount,
        paymentStatus: _trip.paymentStatus,
        feedbackSurveyId: sid, // Set new ID
        authorId: _trip.authorId,
        createdAt: _trip.createdAt,
        status: 'completed',
        groups: _trip.groups,
      );

      await _service.updateFieldTrip(updatedTrip);

      setState(() {
        _trip = updatedTrip;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Anket oluşturuldu')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Filter students
    final filteredStudents = _students.where((s) {
      final name = (s['fullName'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    // Stats Calculation
    int participating = 0;
    int notParticipating = 0;
    int pending = 0;
    int paidCount = _trip.paymentStatus.values.where((v) => v).length;

    for (var s in _students) {
      final sid = s['id'];

      // Determine status
      int status = 0; // 0:Pending, 1:Yes, 2:No

      if (_trip.manualParticipationStatus.containsKey(sid)) {
        final manual = _trip.manualParticipationStatus[sid];
        if (manual == 'participating')
          status = 1;
        else if (manual == 'not_participating')
          status = 2;
        else
          status = 0;
      } else {
        // Fallback to survey
        final resp = _surveyResponses[sid];
        if (resp != null && resp['answers'] != null) {
          final answers = resp['answers'] as Map<String, dynamic>;
          bool joined = false;
          bool rejected = false;
          for (var v in answers.values) {
            final ans = v.toString().toLowerCase();
            if (ans.contains('evet') || ans.contains('katılıyorum'))
              joined = true;
            if (ans.contains('hayır') || ans.contains('katılmıyorum'))
              rejected = true;
          }
          if (joined)
            status = 1;
          else if (rejected)
            status = 2;
        }
      }

      if (status == 1)
        participating++;
      else if (status == 2)
        notParticipating++;
      else
        pending++;
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.indigo.shade900,
            iconTheme: const IconThemeData(color: Colors.white),
            pinned: true,
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                _trip.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.indigo.shade900, Colors.indigo.shade800],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat(
                            'dd MMMM yyyy HH:mm',
                            'tr_TR',
                          ).format(_trip.departureTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _trip.purpose,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Group Manager Button
              IconButton(
                icon: const Icon(Icons.groups),
                tooltip: 'Gruplama ve Öğretmen Atama',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FieldTripGroupManagerScreen(trip: _trip),
                    ),
                  ).then((_) => _loadData()); // Reload when coming back
                },
              ),
              if (_trip.feedbackSurveyId == null)
                IconButton(
                  icon: const Icon(Icons.star_outline),
                  tooltip: 'Geri Dönüş Anketi',
                  onPressed: _createFeedbackSurvey,
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildStatsGrid(
                    participating,
                    notParticipating,
                    pending,
                    paidCount,
                  ),
                  const SizedBox(height: 24),
                  // Search Bar
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Öğrenci Ara...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final student = filteredStudents[index];
              return _buildStudentTile(student);
            }, childCount: filteredStudents.length),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(int p, int np, int pending, int paid) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Katılan',
                p.toString(),
                Colors.green,
                Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Katılmayan',
                np.toString(),
                Colors.red,
                Icons.cancel_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Bekleyen',
                pending.toString(),
                Colors.orange,
                Icons.access_time,
              ),
            ),
          ],
        ),
        if (_trip.isPaid) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toplanan Ücret',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(paid * _trip.amount)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.attach_money, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildStudentTile(Map<String, dynamic> student) {
    final sid = student['id'];

    // Status Determination
    int status = 0; // 0:Pending, 1:Yes, 2:No
    bool isManual = false;

    if (_trip.manualParticipationStatus.containsKey(sid)) {
      isManual = true;
      final manual = _trip.manualParticipationStatus[sid];
      if (manual == 'participating')
        status = 1;
      else if (manual == 'not_participating')
        status = 2;
      else
        status = 0;
    } else {
      final resp = _surveyResponses[sid];
      if (resp != null && resp['answers'] != null) {
        final answers = resp['answers'] as Map<String, dynamic>;
        bool joined = false;
        bool rejected = false;
        for (var v in answers.values) {
          final ans = v.toString().toLowerCase();
          if (ans.contains('evet') || ans.contains('katılıyorum'))
            joined = true;
          if (ans.contains('hayır') || ans.contains('katılmıyorum'))
            rejected = true;
        }
        if (joined)
          status = 1;
        else if (rejected)
          status = 2;
      }
    }

    final paid = _trip.paymentStatus[sid] ?? false;
    final fullName = student['fullName'] ?? 'İsimsiz';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              // Manual Status Change via Pop-up Menu
              final RenderBox box = context.findRenderObject() as RenderBox;
              final offset = box.localToGlobal(Offset.zero);
              showMenu(
                context: context,
                position: RelativeRect.fromLTRB(
                  offset.dx + 50,
                  offset.dy + 50,
                  0,
                  0,
                ),
                items: [
                  const PopupMenuItem(
                    value: 'participating',
                    child: Text('Katılıyor (Manuel)'),
                  ),
                  const PopupMenuItem(
                    value: 'not_participating',
                    child: Text('Katılmıyor (Manuel)'),
                  ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: Text('Sıfırla (Ankete Dön)'),
                  ),
                ],
              ).then((value) {
                if (value != null) {
                  _toggleManualStatus(sid, value == 'reset' ? null : value);
                }
              });
            },
            child: CircleAvatar(
              backgroundColor: isManual
                  ? Colors.amber.shade100
                  : Colors.indigo.shade50,
              child: Text(
                initial,
                style: TextStyle(
                  color: isManual ? Colors.brown : Colors.indigo.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                // Status Chip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (status == 1)
                      _tinyChip('Katılıyor', Colors.green)
                    else if (status == 2)
                      _tinyChip('Katılmıyor', Colors.red)
                    else
                      _tinyChip('Bekleniyor', Colors.orange),

                    if (isManual) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 10, color: Colors.grey[400]),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Manual Status Action Button (visible icon)
              IconButton(
                icon: Icon(Icons.edit_note, color: Colors.blueGrey.shade300),
                tooltip: 'Durumu Düzenle',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: Text('$fullName Durumu'),
                      children: [
                        SimpleDialogOption(
                          onPressed: () {
                            Navigator.pop(c);
                            _toggleManualStatus(sid, 'participating');
                          },
                          child: const Text(
                            '✅ Katılıyor Olarak İşaretle',
                            style: TextStyle(color: Colors.green),
                          ),
                        ),
                        SimpleDialogOption(
                          onPressed: () {
                            Navigator.pop(c);
                            _toggleManualStatus(sid, 'not_participating');
                          },
                          child: const Text(
                            '❌ Katılmıyor Olarak İşaretle',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        SimpleDialogOption(
                          onPressed: () {
                            Navigator.pop(c);
                            _toggleManualStatus(sid, null);
                          },
                          child: const Text(
                            '🔄 Normale Dön (Anketi Kullan)',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              if (_trip.isPaid && status == 1) ...[
                InkWell(
                  onTap: () => _togglePayment(sid, !paid),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: paid ? Colors.green : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          paid ? Icons.check : Icons.attach_money,
                          size: 16,
                          color: paid ? Colors.white : Colors.grey[600],
                        ),
                        if (!paid) const SizedBox(width: 4),
                        if (!paid)
                          Text(
                            'Ödenmedi',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                            ),
                          ),
                        if (paid) const SizedBox(width: 4),
                        if (paid)
                          const Text(
                            'Ödendi',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
