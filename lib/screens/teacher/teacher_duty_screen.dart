import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/school/duty_model.dart';
import '../../services/term_service.dart';
import '../../services/user_permission_service.dart';

class TeacherDutyScreen extends StatefulWidget {
  final String institutionId;
  final String? termId;

  const TeacherDutyScreen({
    Key? key,
    required this.institutionId,
    this.termId,
  }) : super(key: key);

  @override
  State<TeacherDutyScreen> createState() => _TeacherDutyScreenState();
}

class _TeacherDutyScreenState extends State<TeacherDutyScreen> {
  bool _isLoading = true;
  List<DutyScheduleItem> _myDuties = [];
  final Map<String, DutyLocation> _locations = {};
  String? _currentUserId;
  String? _effectiveTermId;
  String? _termName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) return;
      _currentUserId = authUid;

      final userData = await UserPermissionService.loadUserData();
      final docId = userData?['id']?.toString();
      final authUserId = userData?['authUserId']?.toString();
      final tId = userData?['teacherId']?.toString();
      final staffId = userData?['staffId']?.toString();
      final username = userData?['username']?.toString();
      final teacherName = (userData?['fullName'] ?? userData?['name'] ?? '').toString().trim();

      final validTeacherIds = <String>{
        authUid,
        if (docId != null && docId.isNotEmpty) docId,
        if (authUserId != null && authUserId.isNotEmpty) authUserId,
        if (tId != null && tId.isNotEmpty) tId,
        if (staffId != null && staffId.isNotEmpty) staffId,
        if (username != null && username.isNotEmpty) username,
      }.toList();

      // 1. Resolve Effective Term & Term Name
      _effectiveTermId = widget.termId;
      if (_effectiveTermId == null || _effectiveTermId!.isEmpty) {
        final selectedTermId = await TermService().getSelectedTermId();
        final activeTermId = await TermService().getActiveTermId();
        _effectiveTermId = selectedTermId ?? activeTermId;
      }

      if (_effectiveTermId != null && _effectiveTermId!.isNotEmpty) {
        try {
          final termDoc = await FirebaseFirestore.instance
              .collection('terms')
              .doc(_effectiveTermId)
              .get();
          if (termDoc.exists) {
            _termName = (termDoc.data()?['name'] ?? termDoc.data()?['termName'])?.toString();
          }
        } catch (e) {
          debugPrint('Error fetching term details: $e');
        }
      }

      // 2. Fetch valid workPeriod IDs for the active term (for backward compatibility)
      Set<String> validWorkPeriodIds = {};
      final instIds = [
        widget.institutionId,
        widget.institutionId.toUpperCase(),
        widget.institutionId.toLowerCase(),
      ].toSet().toList();

      if (_effectiveTermId != null && _effectiveTermId!.isNotEmpty) {
        try {
          for (final inst in instIds) {
            final wpSnap = await FirebaseFirestore.instance
                .collection('workPeriods')
                .where('institutionId', isEqualTo: inst)
                .where('termId', isEqualTo: _effectiveTermId)
                .get();
            for (var d in wpSnap.docs) {
              validWorkPeriodIds.add(d.id);
            }
          }
        } catch (e) {
          debugPrint('Error fetching workPeriods: $e');
        }
      }

      // 3. Load my duties (Çift Kimlik - DocID, Auth UID, StaffId ve İsim desteği)
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDutyDocs = [];
      final Set<String> seenDutyDocIds = {};

      for (final inst in instIds) {
        for (int i = 0; i < validTeacherIds.length; i += 10) {
          final chunk = validTeacherIds.skip(i).take(10).toList();
          final itemsSnap = await FirebaseFirestore.instance
              .collection('dutyScheduleItems')
              .where('institutionId', isEqualTo: inst)
              .where('teacherId', whereIn: chunk)
              .get();
          for (var doc in itemsSnap.docs) {
            if (seenDutyDocIds.add(doc.id)) {
              allDutyDocs.add(doc);
            }
          }
        }

        // İsim bazlı nöbet atamalarını da tara (Failsafe)
        if (teacherName.isNotEmpty) {
          try {
            final itemsByNameSnap = await FirebaseFirestore.instance
                .collection('dutyScheduleItems')
                .where('institutionId', isEqualTo: inst)
                .where('teacherName', isEqualTo: teacherName)
                .get();
            for (var doc in itemsByNameSnap.docs) {
              if (seenDutyDocIds.add(doc.id)) {
                allDutyDocs.add(doc);
              }
            }
          } catch (_) {}
        }
      }

      final List<DutyScheduleItem> filteredItems = [];
      for (var doc in allDutyDocs) {
        final data = doc.data();
        final itemTermId = data['termId']?.toString().trim();
        final itemPeriodId = data['periodId']?.toString().trim() ?? '';

        bool matches = false;
        if (_effectiveTermId == null || _effectiveTermId!.isEmpty) {
          matches = true;
        } else if (itemTermId != null && itemTermId.isNotEmpty) {
          matches = (itemTermId == _effectiveTermId);
        } else if (itemPeriodId == _effectiveTermId || validWorkPeriodIds.contains(itemPeriodId)) {
          matches = true;
          // Arka planda termId'yi otomatik olarak Firestore'a kaydet (self-healing migration)
          doc.reference.update({'termId': _effectiveTermId}).catchError((_) {});
        }

        if (matches) {
          filteredItems.add(DutyScheduleItem.fromMap(data, doc.id));
        }
      }

      // Dönem filtresi yüzünden hiçbir nöbet eşleşmediyse ama öğretmene ait nöbetler varsa, kullanıcıyı mağdur etmemek için tümünü göster
      if (filteredItems.isEmpty && allDutyDocs.isNotEmpty) {
        for (var doc in allDutyDocs) {
          filteredItems.add(DutyScheduleItem.fromMap(doc.data(), doc.id));
        }
      }

      // 4. Load locations
      final locIds = filteredItems.map((i) => i.locationId).toSet().toList();
      if (locIds.isNotEmpty) {
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

      // 5. Sort duties by dutyDate or weekStart + dayOfWeek
      filteredItems.sort((a, b) {
        final da = a.dutyDate != null
            ? DateTime.tryParse(a.dutyDate!)
            : (a.weekStart?.add(Duration(days: a.dayOfWeek - 1)));
        final db = b.dutyDate != null
            ? DateTime.tryParse(b.dutyDate!)
            : (b.weekStart?.add(Duration(days: b.dayOfWeek - 1)));
        if (da != null && db != null) {
          return da.compareTo(db);
        }
        if (a.weekStart == null || b.weekStart == null) return 0;
        int cmp = a.weekStart!.compareTo(b.weekStart!);
        if (cmp != 0) return cmp;
        return a.dayOfWeek.compareTo(b.dayOfWeek);
      });

      _myDuties = filteredItems;
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

  String _getMonthName(int month) {
    switch (month) {
      case 1: return 'Oca';
      case 2: return 'Şub';
      case 3: return 'Mar';
      case 4: return 'Nis';
      case 5: return 'May';
      case 6: return 'Haz';
      case 7: return 'Tem';
      case 8: return 'Ağu';
      case 9: return 'Eyl';
      case 10: return 'Eki';
      case 11: return 'Kas';
      case 12: return 'Ara';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Nöbetlerim',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Column(
                children: [
                  if (_termName != null && _termName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade50, Colors.indigo.shade50],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blue.shade200.withOpacity(0.6)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(Icons.school_rounded, size: 18, color: Colors.blue.shade700),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Görüntülenen Dönem',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue.shade800.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _termName!,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Aktif Dönem',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _myDuties.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _myDuties.length,
                            itemBuilder: (context, index) {
                              final duty = _myDuties[index];
                              final loc = _locations[duty.locationId];

                              final dutyDate = duty.dutyDate != null
                                  ? DateTime.tryParse(duty.dutyDate!)
                                  : duty.weekStart?.add(Duration(days: duty.dayOfWeek - 1));

                              final now = DateTime.now();
                              final isToday = dutyDate != null &&
                                  dutyDate.year == now.year &&
                                  dutyDate.month == now.month &&
                                  dutyDate.day == now.day;
                              final isPast = dutyDate != null &&
                                  !isToday &&
                                  dutyDate.isBefore(DateTime(now.year, now.month, now.day));

                              return _buildDutyCard(duty, loc, dutyDate, isToday, isPast);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.security_rounded, size: 64, color: Colors.blue.shade300),
            ),
            const SizedBox(height: 18),
            Text(
              _termName != null
                  ? '$_termName için nöbetiniz bulunmuyor'
                  : 'Aktif dönemde tanımlı nöbetiniz bulunmuyor',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nöbet programı yayınlandığında nöbet gün ve yerlerinizi burada görebilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDutyCard(
    DutyScheduleItem duty,
    DutyLocation? loc,
    DateTime? dutyDate,
    bool isToday,
    bool isPast,
  ) {
    final locationName = loc?.name ?? duty.locationName ?? 'Bilinmeyen Yer';
    final hasDescription = loc != null && loc.description.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: isToday ? 2 : 0,
      shadowColor: isToday ? Colors.green.withOpacity(0.2) : Colors.transparent,
      color: isPast ? Colors.grey.shade50 : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday
                ? const Color(0xFF22C55E)
                : isPast
                    ? Colors.grey.shade200
                    : Colors.blue.shade100,
            width: isToday ? 2.0 : 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Date Box
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFFDCFCE7)
                        : isPast
                            ? Colors.grey.shade100
                            : Colors.blue.shade50,
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
                          color: isToday
                              ? const Color(0xFF15803D)
                              : isPast
                                  ? Colors.grey.shade600
                                  : Colors.blue.shade700,
                        ),
                      ),
                      Text(
                        dutyDate != null ? _getMonthName(dutyDate.month) : '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? const Color(0xFF16A34A)
                              : isPast
                                  ? Colors.grey.shade500
                                  : Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Main Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getDayName(duty.dayOfWeek),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isToday
                                  ? const Color(0xFF16A34A)
                                  : isPast
                                      ? Colors.grey.shade600
                                      : Colors.blue.shade800,
                            ),
                          ),
                          if (dutyDate != null) ...[
                            Text(
                              ' • ${DateFormat('yyyy').format(dutyDate)}',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              locationName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (loc != null && loc.group.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Text(
                                loc.group,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (loc != null && loc.startTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade600),
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

                // Status Badge
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, size: 8, color: Color(0xFF15803D)),
                        SizedBox(width: 4),
                        Text(
                          'Bugün',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isPast)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Tamamlandı',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      'Planlandı',
                      style: TextStyle(fontSize: 10.5, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),

            // Nöbet Yeri Açıklaması (Varsa Kartın Alt Kısmında Şık Bir Kutuda Gösterilir)
            if (hasDescription) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isToday
                      ? const Color(0xFFF0FDF4)
                      : isPast
                          ? Colors.grey.shade100
                          : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isToday
                        ? const Color(0xFFBBF7D0)
                        : isPast
                            ? Colors.grey.shade300
                            : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: isToday
                            ? const Color(0xFF16A34A)
                            : isPast
                                ? Colors.grey.shade500
                                : const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nöbet Yeri Notu / Açıklaması',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isToday
                                  ? const Color(0xFF166534)
                                  : isPast
                                      ? Colors.grey.shade700
                                      : const Color(0xFF1E293B),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            loc.description.trim(),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: isPast ? Colors.grey.shade600 : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
