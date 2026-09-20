import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // ⚡ Cache-First RAM & Disk Önbelleği (Anında açılır, sıfır bekleme)
  static List<DutyScheduleItem>? _cachedMyDuties;
  static Map<String, DutyLocation>? _cachedLocations;
  static Map<String, String>? _cachedDutyAmirs;
  static String? _cachedTermName;

  bool _isLoading = true;
  List<DutyScheduleItem> _myDuties = [];
  final Map<String, DutyLocation> _locations = {};
  final Map<String, String> _dutyAmirs = {};
  String? _effectiveTermId;
  String? _termName;

  Future<void> _loadFromDiskCache() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'edukn_duties_${user.uid}_${widget.institutionId}';
      final cachedStr = prefs.getString(key);
      final cachedLocsStr = prefs.getString('edukn_duty_locs_${widget.institutionId}');
      final cachedAmirsStr = prefs.getString('edukn_duty_amirs_${widget.institutionId}');
      final cachedTerm = prefs.getString('edukn_duty_term_${widget.institutionId}');
      if (cachedStr != null && cachedStr.isNotEmpty && _myDuties.isEmpty) {
        final List dec = json.decode(cachedStr);
        final list = dec.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = m['id']?.toString() ?? '';
          return DutyScheduleItem.fromMap(m, id);
        }).toList();

        Map<String, DutyLocation> locs = {};
        if (cachedLocsStr != null) {
          final Map<String, dynamic> locsDec = json.decode(cachedLocsStr);
          locsDec.forEach((k, v) {
            locs[k] = DutyLocation.fromMap(Map<String, dynamic>.from(v as Map));
          });
        }

        Map<String, String> amirs = {};
        if (cachedAmirsStr != null) {
          amirs = Map<String, String>.from(json.decode(cachedAmirsStr));
        }

        if (mounted && list.isNotEmpty) {
          setState(() {
            _myDuties = list;
            _locations.addAll(locs);
            _dutyAmirs.addAll(amirs);
            if (cachedTerm != null) _termName = cachedTerm;
            _isLoading = false;
          });
          _cachedMyDuties = list;
          _cachedLocations = locs;
          _cachedDutyAmirs = amirs;
          _cachedTermName = cachedTerm;
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (_cachedMyDuties != null) {
      _myDuties = List.from(_cachedMyDuties!);
      if (_cachedLocations != null) _locations.addAll(_cachedLocations!);
      if (_cachedDutyAmirs != null) _dutyAmirs.addAll(_cachedDutyAmirs!);
      _termName = _cachedTermName;
      _isLoading = false;
    } else {
      _loadFromDiskCache();
    }
    _loadData(isBackground: _cachedMyDuties != null);
  }

  Future<void> _loadData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() => _isLoading = true);
    }
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) return;

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
          final wpSnaps = await Future.wait(instIds.map((inst) => FirebaseFirestore.instance
              .collection('workPeriods')
              .where('institutionId', isEqualTo: inst)
              .where('termId', isEqualTo: _effectiveTermId)
              .get().catchError((_) => FirebaseFirestore.instance.collection('workPeriods').where(FieldPath.documentId, isEqualTo: 'NO_MATCH_DUMMY_ID').limit(1).get())));
          for (final snap in wpSnaps) {
            for (var d in snap.docs) {
              validWorkPeriodIds.add(d.id);
            }
          }
        } catch (e) {
          debugPrint('Error fetching workPeriods: $e');
        }
      }

      // 3. Load my duties (Çift Kimlik - DocID, Auth UID, StaffId ve İsim desteği - Paralel Sorgulama)
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDutyDocs = [];
      final Set<String> seenDutyDocIds = {};

      final List<Future<QuerySnapshot<Map<String, dynamic>>>> dutyQueries = [];
      for (final inst in instIds) {
        for (int i = 0; i < validTeacherIds.length; i += 10) {
          final chunk = validTeacherIds.skip(i).take(10).toList();
          dutyQueries.add(FirebaseFirestore.instance
              .collection('dutyScheduleItems')
              .where('institutionId', isEqualTo: inst)
              .where('teacherId', whereIn: chunk)
              .get().catchError((_) => FirebaseFirestore.instance.collection('dutyScheduleItems').where(FieldPath.documentId, isEqualTo: 'NO_MATCH_DUMMY_ID').limit(1).get()));
        }

        // İsim bazlı nöbet atamalarını da tara (Failsafe)
        if (teacherName.isNotEmpty) {
          dutyQueries.add(FirebaseFirestore.instance
              .collection('dutyScheduleItems')
              .where('institutionId', isEqualTo: inst)
              .where('teacherName', isEqualTo: teacherName)
              .get().catchError((_) => FirebaseFirestore.instance.collection('dutyScheduleItems').where(FieldPath.documentId, isEqualTo: 'NO_MATCH_DUMMY_ID').limit(1).get()));
        }
      }

      final dutySnaps = await Future.wait(dutyQueries);
      for (final s in dutySnaps) {
        for (var doc in s.docs) {
          if (seenDutyDocIds.add(doc.id)) {
            allDutyDocs.add(doc);
          }
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

      // 4. Load locations and discover Nöbetçi Amir locations
      _locations.clear();
      _dutyAmirs.clear();

      final locSnap = await FirebaseFirestore.instance
          .collection('dutyLocations')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final Set<String> amirLocationIds = {};

      for (var doc in locSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        final loc = DutyLocation.fromMap(data);
        _locations[doc.id] = loc;

        // Yalnızca nöbet yeri ayarlarında "Nöbetçi Amir Yeri" olarak işaretlenen yerler
        if (loc.isAmir == true) {
          amirLocationIds.add(doc.id);
        }
      }

      // Ayrıca alt dönem konfigürasyonunda isAmir olarak işaretlenmiş yerleri de ekle
      if (validWorkPeriodIds.isNotEmpty) {
        for (final wpId in validWorkPeriodIds) {
          try {
            final wpDoc = await FirebaseFirestore.instance.collection('workPeriods').doc(wpId).get();
            final configs = wpDoc.data()?['dutyLocationConfigs'] as Map<String, dynamic>?;
            if (configs != null) {
              configs.forEach((locId, c) {
                if (c is Map && c['isAmir'] == true) {
                  amirLocationIds.add(locId);
                }
              });
            }
          } catch (_) {}
        }
      }

      // 4.1 Load dutyScheduleItems for Nöbetçi Amir (Paralel)
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> amirDocs = [];
      if (amirLocationIds.isNotEmpty) {
        final List<Future<QuerySnapshot<Map<String, dynamic>>>> amirQueries = [];
        final amirIdList = amirLocationIds.toList();
        for (final inst in instIds) {
          for (int i = 0; i < amirIdList.length; i += 10) {
            final chunk = amirIdList.skip(i).take(10).toList();
            amirQueries.add(FirebaseFirestore.instance
                .collection('dutyScheduleItems')
                .where('institutionId', isEqualTo: inst)
                .where('locationId', whereIn: chunk)
                .get()
                .catchError((_) => FirebaseFirestore.instance.collection('dutyScheduleItems').where(FieldPath.documentId, isEqualTo: 'NO_MATCH_DUMMY_ID').limit(1).get()));
          }
        }
        final amirSnaps = await Future.wait(amirQueries);
        for (final s in amirSnaps) {
          amirDocs.addAll(s.docs);
        }
      }

      for (var doc in amirDocs) {
        final data = doc.data();
        final teacherName = (data['teacherName'] ?? '').toString().trim();
        if (teacherName.isEmpty) continue;

        // 1. Exact dutyDate (yyyy-MM-dd)
        final dDate = data['dutyDate']?.toString().trim();
        if (dDate != null && dDate.isNotEmpty) {
          _dutyAmirs[dDate] = teacherName;
        }

        // 2. weekStart + dayOfWeek
        final weekStartStr = data['weekStart']?.toString().trim();
        final dayOfWeek = int.tryParse(data['dayOfWeek']?.toString() ?? '');
        if (weekStartStr != null && dayOfWeek != null) {
          final dt = DateTime.tryParse(weekStartStr);
          if (dt != null) {
            final calculatedDate = dt.add(Duration(days: dayOfWeek - 1));
            final dateKey = DateFormat('yyyy-MM-dd').format(calculatedDate);
            _dutyAmirs[dateKey] = teacherName;
            _dutyAmirs['${DateFormat('yyyy-MM-dd').format(dt)}_$dayOfWeek'] = teacherName;
          }
        }

        // 3. periodId + dayOfWeek and generic dayOfWeek
        final periodId = data['periodId']?.toString().trim() ?? '';
        if (dayOfWeek != null) {
          if (periodId.isNotEmpty) {
            _dutyAmirs['${periodId}_$dayOfWeek'] = teacherName;
          }
          _dutyAmirs['day_$dayOfWeek'] ??= teacherName;
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

      bool hasChanged = _myDuties.length != filteredItems.length;
      if (!hasChanged) {
        for (int i = 0; i < filteredItems.length; i++) {
          if (filteredItems[i].id != _myDuties[i].id) {
            hasChanged = true;
            break;
          }
        }
      }

      _cachedMyDuties = List.from(filteredItems);
      _cachedLocations = Map.from(_locations);
      _cachedDutyAmirs = Map.from(_dutyAmirs);
      _cachedTermName = _termName;

      // 💾 Diske kalıcı kaydet (Uygulama kapatılıp açılsa da 0 ms'de gelir)
      SharedPreferences.getInstance().then((prefs) {
        final key = 'edukn_duties_${authUid}_${widget.institutionId}';
        final dutyList = filteredItems.map((d) {
          final m = d.toMap();
          m['id'] = d.id;
          return m;
        }).toList();
        prefs.setString(key, json.encode(dutyList));

        final locMap = <String, dynamic>{};
        _locations.forEach((k, v) => locMap[k] = v.toMap());
        prefs.setString('edukn_duty_locs_${widget.institutionId}', json.encode(locMap));

        if (_dutyAmirs.isNotEmpty) {
          prefs.setString('edukn_duty_amirs_${widget.institutionId}', json.encode(_dutyAmirs));
        }
        if (_termName != null) {
          prefs.setString('edukn_duty_term_${widget.institutionId}', _termName!);
        }
      }).catchError((_) {});

      if (mounted) {
        setState(() {
          if (hasChanged || _myDuties.isEmpty) {
            _myDuties = filteredItems;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading duties: $e');
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

  String? _getDutyAmir(DutyScheduleItem duty, DateTime? dutyDate) {
    if (dutyDate != null) {
      final dateKey = DateFormat('yyyy-MM-dd').format(dutyDate);
      if (_dutyAmirs.containsKey(dateKey)) {
        return _dutyAmirs[dateKey];
      }
    }

    final dutyDateStr = duty.dutyDate?.trim();
    if (dutyDateStr != null && dutyDateStr.isNotEmpty && _dutyAmirs.containsKey(dutyDateStr)) {
      return _dutyAmirs[dutyDateStr];
    }

    if (duty.weekStart != null) {
      final weekKey = '${DateFormat('yyyy-MM-dd').format(duty.weekStart!)}_${duty.dayOfWeek}';
      if (_dutyAmirs.containsKey(weekKey)) {
        return _dutyAmirs[weekKey];
      }
    }

    final periodKey = '${duty.periodId}_${duty.dayOfWeek}';
    if (_dutyAmirs.containsKey(periodKey)) {
      return _dutyAmirs[periodKey];
    }

    return _dutyAmirs['day_${duty.dayOfWeek}'];
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
    final amirName = _getDutyAmir(duty, dutyDate);

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

            // Günün Nöbetçi Amiri (Varsa kartla birleşik, açıklamanın üstünde kompakt gösterilir)
            if (amirName != null && amirName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isToday
                      ? const Color(0xFFF0FDF4)
                      : isPast
                          ? Colors.grey.shade100
                          : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isToday
                        ? const Color(0xFFBBF7D0)
                        : isPast
                            ? Colors.grey.shade300
                            : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 15,
                      color: isToday
                          ? const Color(0xFF15803D)
                          : isPast
                              ? Colors.grey.shade600
                              : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Nöbetçi Amir: ',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? const Color(0xFF15803D)
                            : isPast
                                ? Colors.grey.shade600
                                : const Color(0xFF475569),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        amirName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isToday
                              ? const Color(0xFF14532D)
                              : isPast
                                  ? Colors.grey.shade800
                                  : const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

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
