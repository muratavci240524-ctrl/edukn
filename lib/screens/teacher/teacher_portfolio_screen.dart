import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';
import '../../services/crypto_service.dart';
import '../portfolio/portfolio_screen.dart';

class TeacherPortfolioScreen extends StatefulWidget {
  final String institutionId;
  final String? initialStudentId;

  const TeacherPortfolioScreen({
    Key? key,
    required this.institutionId,
    this.initialStudentId,
  }) : super(key: key);

  @override
  State<TeacherPortfolioScreen> createState() => _TeacherPortfolioScreenState();
}

class _TeacherPortfolioScreenState extends State<TeacherPortfolioScreen> {
  static final Map<String, List<Map<String, dynamic>>> _staticMemoryCache = {};
  static final Map<String, Map<String, dynamic>> _staticSettingsCache = {};

  bool _isLoading = true;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  Map<String, dynamic>? _selectedStudent;

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String? _filterClassLevel;
  String? _filterClass;

  List<String> _classLevels = [];
  List<String> _classes = [];

  // Context
  String? _activeTermId;
  Map<String, dynamic> _schoolSettings = {};
  String _effectiveInstId = '';

  @override
  void initState() {
    super.initState();
    _effectiveInstId = widget.institutionId.trim().toUpperCase();
    _searchController.addListener(_filterStudents);
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final cacheKey = 'teacher_portfolio_${user.uid}_${_effectiveInstId.isNotEmpty ? _effectiveInstId : widget.institutionId}';

    // 1. Önce hafıza önbelleğine veya SharedPreferences'a bak (0 ms anında açılış)
    if (!forceRefresh) {
      bool cacheFound = false;

      if (_staticMemoryCache.containsKey(cacheKey) && _staticMemoryCache[cacheKey]!.isNotEmpty) {
        _allStudents = List<Map<String, dynamic>>.from(_staticMemoryCache[cacheKey]!);
        if (_staticSettingsCache.containsKey(cacheKey)) {
          _schoolSettings = _staticSettingsCache[cacheKey]!;
        }
        _extractFilters();
        _filterStudents();
        _isLoading = false;
        cacheFound = true;
      } else {
        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedJson = prefs.getString(cacheKey);
          if (cachedJson != null && cachedJson.isNotEmpty) {
            final List<dynamic> decoded = jsonDecode(cachedJson);
            final loaded = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            if (loaded.isNotEmpty) {
              _allStudents = loaded;
              _staticMemoryCache[cacheKey] = loaded;
              _extractFilters();
              _filterStudents();
              _isLoading = false;
              cacheFound = true;
            }
          }
        } catch (e) {
          debugPrint('Cache load error: $e');
        }
      }

      if (cacheFound) {
        if (mounted) setState(() => _isSyncing = true);
        // Arka planda sessizce değişiklik kontrolü yap
        _fetchFromNetwork(cacheKey, isBackgroundSync: true);
        return;
      }
    }

    // Önbellek yoksa veya forceRefresh ise normal yükleme
    if (mounted) setState(() => _isLoading = true);
    await _fetchFromNetwork(cacheKey, isBackgroundSync: false);
  }

  Future<void> _fetchFromNetwork(String cacheKey, {required bool isBackgroundSync}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await CryptoService.init();

      // Parallel context loading
      final futures = await Future.wait([
        UserPermissionService.loadUserData(),
        TermService().getActiveTermId(),
        FirebaseFirestore.instance
            .collection('institutions')
            .doc(_effectiveInstId.isNotEmpty ? _effectiveInstId : widget.institutionId)
            .get(),
      ]);

      final userData = futures[0] as Map<String, dynamic>?;
      _activeTermId = futures[1] as String?;
      final instDoc = futures[2] as DocumentSnapshot<Map<String, dynamic>>;
      if (instDoc.exists) {
        _schoolSettings = instDoc.data() ?? {};
      }

      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().trim().toUpperCase();
      _effectiveInstId = instId;
      final instIds = [instId, instId.toLowerCase(), instId.toUpperCase()].toSet().toList();

      final role = (userData?['role'] ?? '').toString().toLowerCase();
      final branch = (userData?['branch'] ?? userData?['subject'] ?? '').toString().toLowerCase();
      final isGuidanceCounselor = role.contains('rehber') ||
          role.contains('pdr') ||
          branch.contains('rehber') ||
          branch.contains('pdr') ||
          role.contains('admin') ||
          role.contains('yonetici') ||
          role.contains('yönetici') ||
          role.contains('kurucu');

      final List<String> userSchoolTypes = List<String>.from(userData?['schoolTypes'] ?? []);

      final Set<String> validTeacherIds = {user.uid};
      final docId = userData?['id']?.toString();
      if (docId != null && docId.isNotEmpty) validTeacherIds.add(docId);
      final tId = userData?['teacherId']?.toString();
      if (tId != null && tId.isNotEmpty) validTeacherIds.add(tId);
      final authUserId = userData?['authUserId']?.toString();
      if (authUserId != null && authUserId.isNotEmpty) validTeacherIds.add(authUserId);
      final sId = userData?['staffId']?.toString();
      if (sId != null && sId.isNotEmpty) validTeacherIds.add(sId);
      final uName = userData?['username']?.toString();
      if (uName != null && uName.isNotEmpty) validTeacherIds.add(uName);
      final fullName = (userData?['fullName'] ?? userData?['name'] ?? '').toString().trim();

      Set<String> assignedClassIds = {};

      // 1. Fetch assigned classes in parallel
      if (!isGuidanceCounselor) {
        final List<Future<QuerySnapshot>> classQueries = [];

        for (final tid in validTeacherIds) {
          classQueries.add(
            FirebaseFirestore.instance
                .collection('lessonAssignments')
                .where('institutionId', whereIn: instIds)
                .where('teacherIds', arrayContains: tid)
                .where('isActive', isEqualTo: true)
                .get(),
          );
          classQueries.add(
            FirebaseFirestore.instance
                .collection('lessonAssignments')
                .where('institutionId', whereIn: instIds)
                .where('teacherId', isEqualTo: tid)
                .where('isActive', isEqualTo: true)
                .get(),
          );
        }

        if (fullName.isNotEmpty) {
          classQueries.add(
            FirebaseFirestore.instance
                .collection('lessonAssignments')
                .where('institutionId', whereIn: instIds)
                .where('teacherNames', arrayContains: fullName)
                .where('isActive', isEqualTo: true)
                .get(),
          );
        }

        final results = await Future.wait(classQueries);
        for (final snap in results) {
          for (final doc in snap.docs) {
            final cid = doc.get('classId')?.toString();
            if (cid != null && cid.isNotEmpty) {
              // Period/term filter if available
              if (_activeTermId != null && _activeTermId!.isNotEmpty) {
                final docTerm = (doc.data() as Map<String, dynamic>)['termId']?.toString();
                if (docTerm != null && docTerm.isNotEmpty && docTerm != _activeTermId) {
                  continue; // Farklı bir döneme aitse atla
                }
              }
              assignedClassIds.add(cid);
            }
          }
        }
      }

      // 2. Load Students
      List<Map<String, dynamic>> rawStudents = [];

      if (isGuidanceCounselor || assignedClassIds.isEmpty) {
        // Guidance counselor or fallback: Load institution students
        Query query = FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', whereIn: instIds);

        if (userSchoolTypes.isNotEmpty && userSchoolTypes.length <= 10) {
          query = query.where('schoolTypeId', whereIn: userSchoolTypes);
        }

        final snap = await query.get();
        rawStudents = snap.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          data['id'] = d.id;
          return data;
        }).toList();
      } else {
        // Teacher mode: Load students of assigned classes in chunks
        final classList = assignedClassIds.toList();
        final List<Future<QuerySnapshot>> studentFutures = [];

        for (var i = 0; i < classList.length; i += 10) {
          final chunk = classList.skip(i).take(10).toList();
          studentFutures.add(
            FirebaseFirestore.instance
                .collection('students')
                .where('institutionId', whereIn: instIds)
                .where('classId', whereIn: chunk)
                .get(),
          );
        }

        final studentSnaps = await Future.wait(studentFutures);
        for (final snap in studentSnaps) {
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            rawStudents.add(data);
          }
        }
      }

      // 3. Decrypt and Deduplicate
      final seen = <String>{};
      final List<Map<String, dynamic>> decryptedStudents = [];

      for (var s in rawStudents) {
        final sid = s['id'].toString();
        if (seen.add(sid)) {
          final decrypted = CryptoService.decryptMap(s, institutionId: instId);
          decryptedStudents.add(decrypted);
        }
      }

      // Sort by Name
      decryptedStudents.sort((a, b) =>
          (a['fullName'] ?? a['name'] ?? '').toString().compareTo((b['fullName'] ?? b['name'] ?? '').toString()));

      // 4. Update Memory Cache and Local Storage
      _staticMemoryCache[cacheKey] = decryptedStudents;
      _staticSettingsCache[cacheKey] = _schoolSettings;

      try {
        final prefs = await SharedPreferences.getInstance();
        final serializable = decryptedStudents.map((s) {
          final copy = Map<String, dynamic>.from(s);
          copy.removeWhere((k, v) => v is Timestamp || v is DateTime);
          return copy;
        }).toList();
        await prefs.setString(cacheKey, jsonEncode(serializable));
      } catch (e) {
        debugPrint('Cache save error: $e');
      }

      if (mounted) {
        setState(() {
          _allStudents = decryptedStudents;
          _extractFilters();
          _filterStudents();

          if (widget.initialStudentId != null) {
            try {
              _selectedStudent = _allStudents.firstWhere((s) => s['id'] == widget.initialStudentId);
            } catch (_) {}
          }
          _isLoading = false;
          _isSyncing = false;
        });
      }
    } catch (e) {
      debugPrint('Öğretmen portfolyo veri yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSyncing = false;
        });
        if (!isBackgroundSync) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Portfolyo verileri yüklenirken bir sorun oluştu: $e')),
          );
        }
      }
    }
  }

  void _extractFilters() {
    final levels = _allStudents
        .map((s) => s['classLevel']?.toString())
        .where((l) => l != null && l.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    levels.sort((a, b) {
      int? ia = int.tryParse(a);
      int? ib = int.tryParse(b);
      if (ia != null && ib != null) return ia.compareTo(ib);
      if (ia != null) return -1;
      if (ib != null) return 1;
      return a.compareTo(b);
    });

    final branches = _allStudents
        .map((s) => s['className']?.toString())
        .where((b) => b != null && b.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    branches.sort();

    _classLevels = levels;
    _classes = branches;
  }

  void _filterStudents() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredStudents = _allStudents.where((s) {
        // Sadece aktif öğrencileri listele (öğretmen pasifleri görmez)
        final isActive = s['isActive'] ?? true;
        if (!isActive) return false;

        // Level filter
        if (_filterClassLevel != null && _filterClassLevel!.isNotEmpty) {
          if (s['classLevel']?.toString() != _filterClassLevel) return false;
        }

        // Branch filter
        if (_filterClass != null && _filterClass!.isNotEmpty) {
          if (s['className']?.toString() != _filterClass) return false;
        }

        // Search query
        if (query.isNotEmpty) {
          final fullName = (s['fullName'] ?? s['name'] ?? '').toString().toLowerCase();
          final number = (s['studentNumber'] ?? '').toString();
          final tc = (s['tcNo'] ?? '').toString();
          return fullName.contains(query) || number.contains(query) || tc.contains(query);
        }

        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: isWide ? _buildDesktopLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  // DESKTOP LAYOUT (Split View)
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Column: Student List & Filter
        Container(
          width: 380,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200, width: 1.5)),
          ),
          child: Column(
            children: [
              _buildTopHeader(isWide: true),
              _buildSearchAndFilters(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredStudents.isEmpty
                        ? _buildEmptyStudentList()
                        : _buildStudentListView(isWide: true),
              ),
            ],
          ),
        ),

        // Right Column: Student Portfolio Details
        Expanded(
          child: _selectedStudent == null
              ? _buildNoStudentSelectedState()
              : PortfolioDetailView(
                  key: ValueKey(_selectedStudent!['id']),
                  student: _selectedStudent!,
                  institutionId: _effectiveInstId.isNotEmpty ? _effectiveInstId : widget.institutionId,
                  onClose: () => setState(() => _selectedStudent = null),
                  filteredStudents: _filteredStudents,
                  activeTermId: _activeTermId,
                  schoolSettings: _schoolSettings,
                ),
        ),
      ],
    );
  }

  // MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildTopHeader(isWide: false),
        _buildSearchAndFilters(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredStudents.isEmpty
                  ? _buildEmptyStudentList()
                  : _buildStudentListView(isWide: false),
        ),
      ],
    );
  }

  Widget _buildTopHeader({required bool isWide}) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 16, top: 40, bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade900, Colors.indigo.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.indigo.shade900.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Geri Dön',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Öğrenci Portfolyoları',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Öğretmen Rehberlik Portalı',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            tooltip: 'Yenile (Değişiklikleri Güncelle)',
            onPressed: _isSyncing ? null : () => _loadInitialData(forceRefresh: true),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Text(
              '${_filteredStudents.length} Öğrenci',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          // Search Input
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Öğrenci ara (Ad, Soyad, No, TC)...',
                hintStyle: GoogleFonts.inter(color: Colors.blueGrey.shade400, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: Colors.blueGrey.shade400, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filters Row
          Row(
            children: [
              // Class Level Filter
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _filterClassLevel,
                      hint: Text('Seviye', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.black87),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tüm Seviyeler')),
                        ..._classLevels.map((lvl) => DropdownMenuItem(value: lvl, child: Text('$lvl. Sınıf'))),
                      ],
                      onChanged: (val) {
                        setState(() => _filterClassLevel = val);
                        _filterStudents();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Class / Branch Filter
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _filterClass,
                      hint: Text('Şube', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.black87),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tüm Şubeler')),
                        ..._classes.map((cls) => DropdownMenuItem(value: cls, child: Text('$cls Şubesi'))),
                      ],
                      onChanged: (val) {
                        setState(() => _filterClass = val);
                        _filterStudents();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentListView({required bool isWide}) {
    return RefreshIndicator(
      onRefresh: () => _loadInitialData(forceRefresh: true),
      color: Colors.indigo,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _filteredStudents.length,
        itemBuilder: (context, index) {
          final student = _filteredStudents[index];
          final isSelected = isWide && _selectedStudent?['id'] == student['id'];

          return _buildStudentItemCard(student, isSelected: isSelected, isWide: isWide);
        },
      ),
    );
  }

  Widget _buildStudentItemCard(Map<String, dynamic> student, {required bool isSelected, required bool isWide}) {
    final fullName = student['fullName'] ?? student['name'] ?? 'İsimsiz Öğrenci';
    final className = student['className'] ?? student['classLevel'] ?? 'Sınıf Yok';
    final studentNumber = student['studentNumber'] ?? student['schoolNumber'] ?? '-';
    final photoUrl = student['photoUrl'] ?? student['avatarUrl'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.indigo.shade400 : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.indigo.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2))]
            : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: isSelected ? Colors.indigo.shade600 : Colors.indigo.shade50,
          backgroundImage: photoUrl != null && photoUrl.toString().isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl == null || photoUrl.toString().isEmpty
              ? Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : Colors.indigo.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
        title: Text(
          fullName,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.indigo.shade900 : const Color(0xFF1E293B),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                className.toString(),
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'No: $studentNumber',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: isSelected ? Colors.indigo : Colors.grey.shade400,
        ),
        onTap: () {
          if (isWide) {
            setState(() => _selectedStudent = student);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => PortfolioDetailView(
                  student: student,
                  institutionId: _effectiveInstId.isNotEmpty ? _effectiveInstId : widget.institutionId,
                  filteredStudents: _filteredStudents,
                  activeTermId: _activeTermId,
                  schoolSettings: _schoolSettings,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildNoStudentSelectedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.badge_outlined, size: 64, color: Colors.indigo.shade400),
          ),
          const SizedBox(height: 20),
          Text(
            'Öğrenci Portfolyosu İnceleyin',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Detaylı akademik durum, sınav karneleri, gelişim raporları\nve rehberlik kayıtlarını görmek için soldaki listeden bir öğrenci seçin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStudentList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isNotEmpty ? 'Aramaya uygun öğrenci bulunamadı' : 'Tanımlı öğrenci bulunamadı',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Farklı bir arama terimi veya filtre deneyebilirsiniz.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
