import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/school/duty_model.dart';

class TeacherDutyScreen extends StatefulWidget {
  final String institutionId;

  const TeacherDutyScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<TeacherDutyScreen> createState() => _TeacherDutyScreenState();
}

class _TeacherDutyScreenState extends State<TeacherDutyScreen> {
  bool _isLoading = true;
  List<DutyScheduleItem> _myDuties = [];
  Map<String, DutyLocation> _locations = {};
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (_currentUserId == null) return;

      // 1. Load my duties
      final itemsSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('teacherId', isEqualTo: _currentUserId)
          .get();

      final items = itemsSnap.docs
          .map((d) => DutyScheduleItem.fromMap(d.data(), d.id))
          .toList();

      // 2. Load locations
      final locIds = items.map((i) => i.locationId).toSet().toList();
      if (locIds.isNotEmpty) {
        // Firestore whereIn limit is 10, but usually locations aren't many. 
        // If more than 10, we'd need chunks, but let's stick to simple first or fetch all for institution.
        final locSnap = await FirebaseFirestore.instance
            .collection('dutyLocations')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();
        
        for (var doc in locSnap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          _locations[doc.id] = DutyLocation.fromMap(data);
        }
      }

      // Sort duties by weekStart and then dayOfWeek
      items.sort((a, b) {
        if (a.weekStart == null || b.weekStart == null) return 0;
        int cmp = a.weekStart!.compareTo(b.weekStart!);
        if (cmp != 0) return cmp;
        return a.dayOfWeek.compareTo(b.dayOfWeek);
      });

      _myDuties = items;
    } catch (e) {
      debugPrint('Error loading duties: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getDayName(int day) {
    switch (day) {
      case 1: return 'Pazartesi';
      case 2: return 'Salı';
      case 3: return 'Çarşamba';
      case 4: return 'Perşembe';
      case 5: return 'Cuma';
      case 6: return 'Cumartesi';
      case 7: return 'Pazar';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Nöbetlerim',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myDuties.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _myDuties.length,
                    itemBuilder: (context, index) {
                      final duty = _myDuties[index];
                      final loc = _locations[duty.locationId];
                      final isPast = duty.weekStart != null && 
                          duty.weekStart!.add(Duration(days: duty.dayOfWeek)).isBefore(DateTime.now());

                      return _buildDutyCard(duty, loc, isPast);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.security, size: 64, color: Colors.blue.shade300),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tanımlı nöbetiniz bulunmuyor',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nöbet programı açıklandığında burada görebilirsiniz.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDutyCard(DutyScheduleItem duty, DutyLocation? loc, bool isPast) {
    final dutyDate = duty.weekStart?.add(Duration(days: duty.dayOfWeek - 1));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: isPast ? Colors.grey.shade50 : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPast ? Colors.grey.shade200 : Colors.blue.shade100, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isPast ? Colors.grey.shade100 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dutyDate != null ? DateFormat('dd').format(dutyDate) : '??',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isPast ? Colors.grey.shade600 : Colors.blue.shade700,
                    ),
                  ),
                  Text(
                    dutyDate != null ? DateFormat('MMM').format(dutyDate) : '',
                    style: TextStyle(
                      fontSize: 12,
                      color: isPast ? Colors.grey.shade500 : Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getDayName(duty.dayOfWeek),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isPast ? Colors.grey : Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc?.name ?? 'Bilinmeyen Yer',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (loc != null && loc.startTime.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${loc.startTime} - ${loc.endTime}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (isPast)
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                 decoration: BoxDecoration(
                   color: Colors.grey.shade200,
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: const Text('Tamamlandı', style: TextStyle(fontSize: 10, color: Colors.grey)),
               )
            else
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
