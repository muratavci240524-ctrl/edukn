import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../services/term_service.dart';
import '../class_schedule_guide_page.dart';
import 'schedule_editor_screen.dart';

/// Donem listesi - kullanici buradan bir alt donem secip editorе gecir.
class ClassScheduleScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassScheduleScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ClassScheduleScreen> createState() => _ClassScheduleScreenState();
}

class _ClassScheduleScreenState extends State<ClassScheduleScreen> {
  String? _selectedPeriodId;
  Map<String, dynamic>? _selectedPeriod;
  String? _currentTermId;
  bool _isViewingPastTerm = false;
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _loadTermFilter();
  }

  Future<void> _loadTermFilter() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm =
            selectedTermId != null && selectedTermId != activeTermId;
      });
    }
  }

  void _showShareOptions(String periodId, String periodName) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Programi Paylas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(periodName,
                style: TextStyle(color: Colors.grey.shade600)),
            SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Icon(Icons.person, color: Colors.blue),
              ),
              title: Text('Ogretmen Programi'),
              subtitle: Text('Ogretmene ozel program paylas'),
              onTap: () {
                Navigator.pop(context);
                _showTeacherShareSelector(periodId);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.publish, color: Colors.green),
              ),
              title: Text('Herkese Yayinla'),
              subtitle: Text('Programi tum kullanicilara yayinla'),
              onTap: () {
                Navigator.pop(context);
                _publishSchedule(periodId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTeacherShareSelector(String periodId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person_rounded, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            const Text('Öğretmen Programı Yayınla'),
          ],
        ),
        content: const Text(
          'Ders programı yayınlanarak tüm öğretmenlerin ders programı ekranına iletilecektir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _publishSchedule(periodId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yayınla ve İlet'),
          ),
        ],
      ),
    );
  }

  Future<void> _publishSchedule(String periodId) async {
    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(periodId)
          .update({'schedulePublished': true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Program yayinlandi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unpublishSchedule(String periodId) async {
    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(periodId)
          .update({'schedulePublished': false});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Program yayindan kaldirildi'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedPeriodId != null && _selectedPeriod != null) {
      return ScheduleEditorScreen(
        periodId: _selectedPeriodId!,
        periodData: _selectedPeriod!,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        isViewingPastTerm: _isViewingPastTerm,
        onBack: () {
          setState(() {
            _selectedPeriodId = null;
            _selectedPeriod = null;
          });
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.grey.shade800),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ders Programi',
                style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(widget.schoolTypeName,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: Colors.purple),
            tooltip: 'Program Hazirlama Rehberi',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ClassScheduleGuidePage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.purple.shade100,
                          Colors.indigo.shade50
                        ]),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.calendar_view_week_rounded,
                          size: 38, color: Colors.purple.shade700),
                    ),
                    const SizedBox(height: 12),
                    const Text('Ders Programi Olustur',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    Text('Program olusturmak icin bir alt donem secin',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              Expanded(child: _buildPeriodsList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Henuz alt donem tanimlanmamis',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Once Calisma Takvimi\'nden donem ekleyin',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          );
        }

        var periods = snapshot.data!.docs.toList();
        if (_currentTermId != null) {
          periods = periods.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['termId'] == _currentTermId;
          }).toList();
        }
        periods.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate =
              (aData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bDate =
              (bData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });
        if (periods.isEmpty) {
          return Center(
            child: Text('Bu donemde alt donem bulunamadi',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }

        return ListView.builder(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: periods.length,
          itemBuilder: (context, index) {
            final doc = periods[index];
            final data = doc.data() as Map<String, dynamic>;
            final startDate =
                (data['startDate'] as Timestamp?)?.toDate();
            final endDate = (data['endDate'] as Timestamp?)?.toDate();
            final periodName = data['periodName'] ?? 'Isimsiz Donem';
            final isPublished = data['schedulePublished'] == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPublished
                      ? Colors.green.shade200
                      : Colors.grey.shade200,
                  width: isPublished ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedPeriodId = doc.id;
                      _selectedPeriod = {...data, 'id': doc.id};
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isPublished
                                    ? Colors.green.shade50
                                    : Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPublished
                                      ? Colors.green.shade200
                                      : Colors.purple.shade100,
                                ),
                              ),
                              child: Icon(
                                Icons.calendar_month_rounded,
                                color: isPublished
                                    ? Colors.green.shade700
                                    : Colors.purple.shade700,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        periodName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      if (isPublished)
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: Colors
                                                    .green.shade300),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                  Icons
                                                      .check_circle_rounded,
                                                  size: 12,
                                                  color: Colors
                                                      .green.shade700),
                                              const SizedBox(width: 3),
                                              Text('Yayinda',
                                                  style: TextStyle(
                                                      color: Colors
                                                          .green.shade800,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (startDate != null &&
                                      endDate != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                            Icons.access_time_rounded,
                                            size: 13,
                                            color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}',
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade400, size: 24),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.grey.shade100),
                          ),
                          child: Row(
                            children: [
                              Text('Programi Ac',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple.shade700)),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: Colors.purple.shade700),
                              const Spacer(),
                              InkWell(
                                onTap: () => _showShareOptions(
                                    doc.id, periodName),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.share_outlined,
                                          size: 15,
                                          color: Colors.blue.shade700),
                                      const SizedBox(width: 4),
                                      Text('Paylas',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  Colors.blue.shade700)),
                                    ],
                                  ),
                                ),
                              ),
                              if (isPublished) ...[
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded,
                                      size: 18,
                                      color: Colors.grey.shade700),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onSelected: (value) {
                                    if (value == 'unpublish') {
                                      _unpublishSchedule(doc.id);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'unpublish',
                                      child: Row(
                                        children: [
                                          Icon(
                                              Icons
                                                  .visibility_off_outlined,
                                              color: Colors.orange,
                                              size: 18),
                                          SizedBox(width: 8),
                                          Text('Yayindan Kaldir'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}