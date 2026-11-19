import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/class_model.dart';
import '../models/school/official_document_model.dart';
import 'term_service.dart';
import 'user_permission_service.dart';

class OfficialDocumentContextService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final Map<String, SchoolDocContext> _contextCache = {};
  static final Map<String, DateTime> _contextCacheTime = {};

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ç', 'ç')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ü', 'ü')
        .toLowerCase();
  }

  /// "NIDA KAÇMAZ" ile "NİDA KAÇMAZ" gibi ASCII/Türkçe harf farklarını tek kişide birleştiren anahtar
  static String _personDedupKey(String input) {
    return _normTr(input)
        .replaceAll('ı', 'i')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _turkishCharScore(String input) {
    return RegExp(r'[İıŞşĞğÜüÖöÇç]').allMatches(input).length;
  }

  static int _turkishCompare(String a, String b) {
    const alphabet = ' 0123456789abcçdefgğhıijklmnoöprsştuüvyz';
    final aL = _normTr(a);
    final bL = _normTr(b);
    final minLen = aL.length < bL.length ? aL.length : bL.length;
    for (int i = 0; i < minLen; i++) {
      final ca = aL[i];
      final cb = bL[i];
      if (ca != cb) {
        final ia = alphabet.indexOf(ca);
        final ib = alphabet.indexOf(cb);
        if (ia != -1 && ib != -1) return ia.compareTo(ib);
        return ca.compareTo(cb);
      }
    }
    return aL.length.compareTo(bL.length);
  }

  /// Kurum, yönetici, öğretmen, sınıf ve ders atamalarını tek seferde yükler
  Future<SchoolDocContext> loadContext({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    List<String>? allowedClassIds,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'v5_${institutionId}_${schoolTypeId}_$schoolTypeName';
    final cachedAt = _contextCacheTime[cacheKey];
    if (!forceRefresh &&
        _contextCache.containsKey(cacheKey) &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt).inSeconds < 90) {
      return _contextCache[cacheKey]!;
    }

    final instVariants = {
      institutionId,
      institutionId.toUpperCase(),
      institutionId.toLowerCase(),
    }.where((e) => e.isNotEmpty).toList();

    // 1. Kullanıcı verisi ve aktif dönem
    final userData = await UserPermissionService.loadUserData();
    final authUser = FirebaseAuth.instance.currentUser;

    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    String academicYear = '$startYear-${startYear + 1}';
    String activeTermLabel = now.month >= 2 && now.month <= 7 ? '2. Dönem' : '1. Dönem';
    String activeTermId = '';

    try {
      final selectedTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      if (selectedTermId != null && selectedTermId.isNotEmpty) {
        activeTermId = selectedTermId;
        final termDoc = await _db.collection('terms').doc(selectedTermId).get();
        if (termDoc.exists) {
          final td = termDoc.data() ?? {};
          final tName = (td['name'] ?? td['termName'] ?? '').toString().trim();
          if (tName.isNotEmpty) {
            final yearMatch = RegExp(r'20\d{2}\s*-\s*20\d{2}').firstMatch(tName);
            if (yearMatch != null) {
              academicYear = yearMatch.group(0)!.replaceAll(' ', '');
            }
            if (tName.contains('2')) {
              activeTermLabel = '2. Dönem';
            } else if (tName.contains('1')) {
              activeTermLabel = '1. Dönem';
            }
          }
        }
      }
    } catch (_) {}

    // 2. Okul dokümanı
    String schoolName = schoolTypeName;
    String city = '';
    String district = '';
    String address = '';
    String phone = '';
    String email = '';
    String? logoUrl;

    try {
      DocumentSnapshot<Map<String, dynamic>>? schoolDoc;
      if (instVariants.isNotEmpty) {
        final byField = await _db
            .collection('schools')
            .where('institutionId', whereIn: instVariants)
            .limit(1)
            .get();
        if (byField.docs.isNotEmpty) {
          schoolDoc = byField.docs.first;
        }
      }
      if (schoolDoc == null) {
        final byId = await _db.collection('schools').doc(institutionId).get();
        if (byId.exists) schoolDoc = byId;
      }
      if (schoolDoc != null && schoolDoc.exists) {
        final sd = schoolDoc.data() ?? {};
        final rawName = (sd['schoolName'] ?? sd['name'] ?? '').toString().trim();
        if (rawName.isNotEmpty) {
          schoolName = schoolTypeName.isNotEmpty &&
                  !rawName.toLowerCase().contains(schoolTypeName.toLowerCase())
              ? '$rawName $schoolTypeName'
              : rawName;
        }
        city = (sd['city'] ?? sd['province'] ?? sd['il'] ?? '').toString().trim();
        district = (sd['district'] ?? sd['ilce'] ?? '').toString().trim();
        address = (sd['schoolAddress'] ?? sd['address'] ?? '').toString().trim();
        phone = (sd['schoolPhone'] ?? sd['phone'] ?? '').toString().trim();
        email = (sd['schoolEmail'] ?? sd['email'] ?? '').toString().trim();
        logoUrl = sd['logoUrl']?.toString();
      }
    } catch (_) {}

    // 2.5. Kurumdaki Okul Türleri (Aktif okul türünü diğer okul türlerinden kesin ayırmak için)
    final Set<String> allSchoolTypeIds = {};
    final Set<String> targetLocationNames = {};
    final Map<String, int> categoryTypeCounts = {};
    String activeTypeCategory = '';

    if (schoolTypeName.trim().isNotEmpty) {
      targetLocationNames.add(_normTr(schoolTypeName));
    }

    try {
      final stSnap = await _db
          .collection('schoolTypes')
          .where('institutionId', whereIn: instVariants.isNotEmpty ? instVariants : [institutionId])
          .get();

      for (final d in stSnap.docs) {
        allSchoolTypeIds.add(d.id);
        final st = d.data();
        final cat = _normTr((st['schoolType'] ?? '').toString());
        if (cat.isNotEmpty) {
          categoryTypeCounts[cat] = (categoryTypeCounts[cat] ?? 0) + 1;
        }
        if (schoolTypeId.isNotEmpty && d.id == schoolTypeId) {
          for (final key in ['schoolTypeName', 'typeName', 'name']) {
            final v = _normTr((st[key] ?? '').toString());
            if (v.isNotEmpty) targetLocationNames.add(v);
          }
          if (cat.isNotEmpty) activeTypeCategory = cat;
        } else if (schoolTypeId.isEmpty && schoolTypeName.trim().isNotEmpty) {
          final stName = _normTr(
            (st['schoolTypeName'] ?? st['typeName'] ?? st['name'] ?? '').toString(),
          );
          if (stName == _normTr(schoolTypeName) && cat.isNotEmpty) {
            activeTypeCategory = cat;
          }
        }
      }
      if (activeTypeCategory.isNotEmpty &&
          (categoryTypeCounts[activeTypeCategory] ?? 0) <= 1) {
        targetLocationNames.add(activeTypeCategory);
      }
    } catch (_) {}

    // 3. Ders Atamaları ve Kurlu Ders Grupları Ön Taraması
    // (Hem okul türü öğretmen doğrulaması hem de ŞÖK tam öğretmen listesi için)
    final Set<String> branchSet = {};
    final Map<String, List<String>> classTeachersByClass = {};
    final Set<String> teacherIdsInThisType = {};
    final Set<String> teacherNamesInThisType = {};
    final Set<String> teacherIdsInOtherTypes = {};
    final Set<String> teacherNamesInOtherTypes = {};
    final List<Map<String, dynamic>> rawAssignments = [];
    final List<Map<String, dynamic>> rawTrackGroups = [];

    try {
      final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
      final assignSnap = await _db
          .collection('lessonAssignments')
          .where('institutionId', whereIn: instFilter)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in assignSnap.docs) {
        final d = doc.data();
        rawAssignments.add(d);
        final docStId = (d['schoolTypeId'] ?? '').toString().trim();
        final isForThisSchoolType =
            schoolTypeId.isEmpty || docStId.isEmpty || docStId == schoolTypeId;

        final List<dynamic> tIds = [
          if (d['teacherIds'] is Iterable) ...(d['teacherIds'] as Iterable),
          if (d['teacherId'] != null) d['teacherId'],
        ];
        final List<dynamic> tNames = [
          if (d['teacherNames'] is Iterable) ...(d['teacherNames'] as Iterable),
          if (d['teacherName'] != null) d['teacherName'],
        ];

        if (isForThisSchoolType && (schoolTypeId.isEmpty || docStId == schoolTypeId)) {
          for (final id in tIds) {
            final s = id.toString().trim();
            if (s.isNotEmpty) teacherIdsInThisType.add(s);
          }
          for (final n in tNames) {
            final s = _normTr(n.toString());
            if (s.isNotEmpty) teacherNamesInThisType.add(s);
          }
          final lessonName = (d['lessonName'] ?? '').toString().trim();
          if (lessonName.isNotEmpty) branchSet.add(lessonName);
        } else if (docStId.isNotEmpty && docStId != schoolTypeId) {
          for (final id in tIds) {
            final s = id.toString().trim();
            if (s.isNotEmpty) teacherIdsInOtherTypes.add(s);
          }
          for (final n in tNames) {
            final s = _normTr(n.toString());
            if (s.isNotEmpty) teacherNamesInOtherTypes.add(s);
          }
        }
      }
    } catch (_) {}

    // 3B. Kurlu Ders Grupları (courseGroups - type != 'club'; örn. İngilizce, Almanca seviye kurları)
    try {
      final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
      final cgSnap = await _db
          .collection('courseGroups')
          .where('institutionId', whereIn: instFilter)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in cgSnap.docs) {
        final d = doc.data();
        final typeRaw = (d['type'] ?? 'track').toString().trim().toLowerCase();
        // Sosyal kulüpleri (club) akademik ŞÖK ders öğretmenlerine karıştırma; yalnızca akademik kur gruplarını al
        if (typeRaw == 'club') continue;
        rawTrackGroups.add(d);

        final docStId = (d['schoolTypeId'] ?? '').toString().trim();
        final subGroups = d['subGroups'] is List ? (d['subGroups'] as List) : const [];
        final List<String> groupTeacherIds = [];
        final List<String> groupTeacherNames = [];
        for (final sg in subGroups) {
          if (sg is! Map) continue;
          if (sg['teacherIds'] is Iterable) {
            for (final id in (sg['teacherIds'] as Iterable)) {
              final s = id.toString().trim();
              if (s.isNotEmpty) groupTeacherIds.add(s);
            }
          }
          if (sg['teacherNames'] is Iterable) {
            for (final n in (sg['teacherNames'] as Iterable)) {
              final s = n.toString().trim();
              if (s.isNotEmpty) groupTeacherNames.add(s);
            }
          }
        }

        if (schoolTypeId.isEmpty || docStId == schoolTypeId) {
          teacherIdsInThisType.addAll(groupTeacherIds);
          for (final n in groupTeacherNames) {
            final norm = _normTr(n);
            if (norm.isNotEmpty) teacherNamesInThisType.add(norm);
          }
          final lessonName = (d['lessonName'] ?? '').toString().trim();
          if (lessonName.isNotEmpty) branchSet.add(lessonName);
        } else if (docStId.isNotEmpty) {
          teacherIdsInOtherTypes.addAll(groupTeacherIds);
          for (final n in groupTeacherNames) {
            final norm = _normTr(n);
            if (norm.isNotEmpty) teacherNamesInOtherTypes.add(norm);
          }
        }
      }
    } catch (_) {}

    // 4. Sadece Bu Okul Türünde Görev Yapan Öğretmen ve İdareciler
    // (+ Kurum genelinde teacherId -> Ad Soyad / Branş çözümleme haritası)
    final List<DocStaffItem> allStaff = [];
    final List<DocStaffItem> vicePrincipals = [];
    final List<DocStaffItem> counselors = [];
    final Map<String, String> userIdToName = {};
    final Map<String, String> userIdToBranch = {};
    String principalName = '';
    DocStaffItem? currentUserItem;
    final bool filterBySchoolType =
        schoolTypeId.isNotEmpty || targetLocationNames.isNotEmpty;

    bool matchesThisSchoolTypeLocation(String loc) {
      final n = _normTr(loc);
      if (n.isEmpty || n == '-') return false;
      return targetLocationNames.contains(n);
    }

    try {
      final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
      final usersSnap = await _db
          .collection('users')
          .where('institutionId', whereIn: instFilter)
          .get();

      for (final doc in usersSnap.docs) {
        final u = doc.data();
        if (u['isActive'] == false) continue;

        final first = (u['firstName'] ?? '').toString().trim();
        final last = (u['lastName'] ?? '').toString().trim();
        final fullName =
            (u['fullName'] ?? u['name'] ?? u['displayName'] ?? '$first $last')
                .toString()
                .trim();
        if (fullName.isEmpty) continue;

        final authUid = authUser?.uid ?? '';
        final isAuthSelf = doc.id == authUid ||
            (u['authUserId'] ?? '').toString() == authUid ||
            (authUser?.email != null &&
                (u['email'] ?? '').toString().toLowerCase() ==
                    authUser!.email!.toLowerCase());

        final titleRaw = (u['title'] ?? '').toString().trim();
        final roleOnlyRaw = (u['role'] ?? '').toString().trim();
        final effectiveRoleRaw =
            (titleRaw.isNotEmpty && titleRaw != '-') ? titleRaw : roleOnlyRaw;

        final rNorm = _normTr(roleOnlyRaw);
        final tNorm = _normTr(titleRaw);
        final effNorm = _normTr(effectiveRoleRaw);

        // Öğrenci ve velileri kesin hariç tut
        if (rNorm == 'student' ||
            rNorm == 'ogrenci' ||
            rNorm == 'öğrenci' ||
            rNorm == 'parent' ||
            rNorm == 'veli' ||
            tNorm == 'student' ||
            tNorm == 'ogrenci') {
          continue;
        }

        final rawBranch =
            (u['branch'] ?? u['branchName'] ?? u['lesson'] ?? '').toString().trim();
        final cleanBranch = (rawBranch == '-' ||
                _normTr(rawBranch) == 'ogretmen' ||
                _normTr(rawBranch) == 'mudur' ||
                _normTr(rawBranch) == 'mudur_yardimcisi')
            ? ''
            : rawBranch;

        // Ders/kur/sınıf atamalarında yalnızca teacherId kayıtlı olduğunda isim ve branşı eksiksiz çözebilmek için sakla
        userIdToName[doc.id] = fullName;
        if (cleanBranch.isNotEmpty) {
          userIdToBranch[doc.id] = cleanBranch;
        }
        final linkedAuthId = (u['authUserId'] ?? '').toString().trim();
        if (linkedAuthId.isNotEmpty) {
          userIdToName.putIfAbsent(linkedAuthId, () => fullName);
          if (cleanBranch.isNotEmpty) {
            userIdToBranch.putIfAbsent(linkedAuthId, () => cleanBranch);
          }
        }

        if (isAuthSelf) {
          currentUserItem = DocStaffItem(
            id: doc.id,
            fullName: fullName,
            role: effectiveRoleRaw,
            branch: cleanBranch,
            phone: (u['phone'] ?? '').toString().trim(),
          );
        }

        // Eğitim-öğretim ve okul idaresi dışındaki merkez/destek kadrolarını (Genel Müdür, İK, Muhasebe, Hizmetli vb.) imza sirküsüne alma
        final isSchoolEducatorTitle = tNorm == 'ogretmen' ||
            tNorm == 'öğretmen' ||
            tNorm == 'teacher' ||
            tNorm == 'mudur' ||
            tNorm == 'müdür' ||
            tNorm == 'okul muduru' ||
            tNorm == 'okul müdürü' ||
            tNorm == 'okul_muduru' ||
            tNorm == 'mudur_yardimcisi' ||
            tNorm == 'mudur yardimcisi' ||
            tNorm == 'müdür yardımcısı' ||
            tNorm.contains('rehber') ||
            tNorm == 'pdr';

        const nonSchoolRoles = {
          'genel_mudur',
          'genel mudur',
          'genel müdür',
          'admin',
          'superadmin',
          'kurucu',
          'hr',
          'insan_kaynaklari',
          'insan kaynakları',
          'muhasebe',
          'satin_alma',
          'satın alma',
          'depo',
          'destek_hizmetleri',
          'destek hizmetleri',
          'hizmetli',
          'memur',
          'personel',
          'guvenlik',
          'güvenlik',
          'sofor',
          'şoför',
          'asci',
          'aşçı',
          'temizlik',
          'diger',
          'diğer',
        };

        if (!isSchoolEducatorTitle &&
            (nonSchoolRoles.contains(effNorm) || nonSchoolRoles.contains(rNorm))) {
          continue;
        }

        // OKUL TÜRÜ KESİN FİLTRESİ: Diğer okul türlerine (İlkokul, Lise, Anaokulu vb.) ait müdür, müdür yardımcısı ve öğretmenleri kesinlikle alma!
        if (filterBySchoolType) {
          final List<String> workLocs = [];
          if (u['workLocations'] is List) {
            for (final item in (u['workLocations'] as List)) {
              final s = item.toString().trim();
              if (s.isNotEmpty && s != '-') workLocs.add(s);
            }
          } else if (u['workLocation'] != null) {
            final s = u['workLocation'].toString().trim();
            if (s.isNotEmpty && s != '-') workLocs.add(s);
          }

          final singleStId = (u['schoolTypeId'] ?? '').toString().trim();
          final List<String> userStList = [];
          final rawStList = u['schoolTypes'] ?? u['schoolTypeIds'];
          if (rawStList is List) {
            for (final item in rawStList) {
              final s = item.toString().trim();
              if (s.isNotEmpty && s != '-') userStList.add(s);
            }
          }

          final inThisLessons = teacherIdsInThisType.contains(doc.id) ||
              teacherNamesInThisType.contains(_normTr(fullName));
          final inOtherLessons = teacherIdsInOtherTypes.contains(doc.id) ||
              teacherNamesInOtherTypes.contains(_normTr(fullName));

          bool belongsToThisSchoolType = false;

          if (workLocs.isNotEmpty) {
            belongsToThisSchoolType = workLocs.any(matchesThisSchoolTypeLocation);
          } else if (singleStId.isNotEmpty && schoolTypeId.isNotEmpty) {
            belongsToThisSchoolType = singleStId == schoolTypeId;
          } else if (userStList.isNotEmpty) {
            final hasThisType =
                (schoolTypeId.isNotEmpty && userStList.contains(schoolTypeId)) ||
                userStList.any(matchesThisSchoolTypeLocation);

            if (hasThisType) {
              final hasAllTypesByDefault = allSchoolTypeIds.length > 1 &&
                  userStList.toSet().containsAll(allSchoolTypeIds);

              if (hasAllTypesByDefault) {
                if (u['schoolTypePermissions'] is Map &&
                    (u['schoolTypePermissions'] as Map).isNotEmpty &&
                    schoolTypeId.isNotEmpty) {
                  final perms = u['schoolTypePermissions'] as Map;
                  belongsToThisSchoolType = perms.containsKey(schoolTypeId) &&
                      perms[schoolTypeId] != null &&
                      perms[schoolTypeId] != false &&
                      perms[schoolTypeId] != 'none';
                } else if (inThisLessons) {
                  belongsToThisSchoolType = true;
                } else if (inOtherLessons) {
                  belongsToThisSchoolType = false;
                } else {
                  belongsToThisSchoolType = false;
                }
              } else {
                belongsToThisSchoolType = true;
              }
            }
          } else {
            belongsToThisSchoolType = inThisLessons;
          }

          if (!belongsToThisSchoolType) continue;
        }

        if (cleanBranch.isNotEmpty) branchSet.add(cleanBranch);

        final item = DocStaffItem(
          id: doc.id,
          fullName: fullName,
          role: effectiveRoleRaw,
          branch: cleanBranch,
          phone: (u['phone'] ?? '').toString().trim(),
        );
        allStaff.add(item);

        final isPrincipal = effNorm == 'müdür' ||
            effNorm == 'mudur' ||
            effNorm == 'okul müdürü' ||
            effNorm == 'okul muduru' ||
            effNorm == 'okul_muduru' ||
            effNorm == 'principal';
        final isVicePrincipal = effNorm == 'mudur_yardimcisi' ||
            effNorm.contains('müdür yardımcısı') ||
            effNorm.contains('mudur yardimcisi') ||
            effNorm == 'manager';

        if (isPrincipal) {
          principalName = fullName;
        } else if (isVicePrincipal) {
          vicePrincipals.add(item);
        }

        final branchNorm = _normTr(cleanBranch);
        if (branchNorm.contains('rehber') ||
            branchNorm.contains('psikolojik') ||
            effNorm.contains('rehber') ||
            effNorm == 'pdr') {
          counselors.add(item);
        }
      }
    } catch (_) {}

    if (currentUserItem == null && userData != null) {
      final fn = (userData['fullName'] ?? userData['name'] ?? authUser?.displayName ?? '').toString().trim();
      if (fn.isNotEmpty) {
        currentUserItem = DocStaffItem(
          id: authUser?.uid ?? '',
          fullName: fn,
          role: (userData['title'] ?? userData['role'] ?? '').toString(),
          branch: (userData['branch'] ?? userData['branchName'] ?? '').toString(),
        );
      }
    }

    if (principalName.isEmpty) {
      principalName = 'Okul Müdürü';
    }

    allStaff.sort((a, b) => _turkishCompare(a.fullName, b.fullName));
    vicePrincipals.sort((a, b) => _turkishCompare(a.fullName, b.fullName));
    counselors.sort((a, b) => _turkishCompare(a.fullName, b.fullName));

    // 5. Sınıflar (Şube Rehber Öğretmeni + Sınıf Rehber/PDR Danışmanı dahil)
    final List<DocClassItem> classItems = [];
    final Map<String, String> classIdToName = {};
    final Set<String> knownClassNames = {};
    final Map<int, List<String>> classLevelToNames = {};
    final Map<String, String> classCounselorByClassName = {};

    try {
      final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
      Query clsQuery = _db
          .collection('classes')
          .where('institutionId', whereIn: instFilter)
          .where('isActive', isEqualTo: true);
      if (schoolTypeId.isNotEmpty) {
        clsQuery = clsQuery.where('schoolTypeId', isEqualTo: schoolTypeId);
      }
      final clsSnap = await clsQuery.get();
      var models = clsSnap.docs
          .map((d) => ClassModel.fromMap(d.data() as Map<String, dynamic>, d.id))
          .toList();

      // Tüm şubelerin ID->Ad haritasını sakla (allowedClassIds daraltmasından önce)
      for (final m in models) {
        final cid = (m.id ?? '').trim();
        final cname = m.className.trim();
        if (cname.isNotEmpty) {
          if (cid.isNotEmpty) classIdToName[cid] = cname;
          knownClassNames.add(cname);
          classLevelToNames.putIfAbsent(m.classLevel, () => []).add(cname);
        }
      }

      if (allowedClassIds != null && allowedClassIds.isNotEmpty) {
        models = models.where((c) => allowedClassIds.contains(c.id)).toList();
      }
      models.sort((a, b) {
        final cmp = a.classLevel.compareTo(b.classLevel);
        return cmp != 0 ? cmp : a.className.compareTo(b.className);
      });

      for (final d in clsSnap.docs) {
        final data = d.data() as Map<String, dynamic>;
        final match = models.where((m) => m.id == d.id);
        if (match.isEmpty) continue;
        final m = match.first;

        final advisorId =
            (data['classTeacherId'] ?? data['advisorTeacherId'] ?? '').toString().trim();
        final rawAdvisorName = (data['advisorTeacherName'] ??
                data['classTeacherName'] ??
                '')
            .toString()
            .trim();
        final resolvedAdvisor = rawAdvisorName.isNotEmpty
            ? rawAdvisorName
            : (advisorId.isNotEmpty ? (userIdToName[advisorId] ?? '') : '');

        final counselorId =
            (data['guidanceCounselorId'] ?? data['counselorId'] ?? '').toString().trim();
        final rawCounselorName = (data['guidanceCounselorName'] ??
                data['guidanceTeacher'] ??
                data['counselorName'] ??
                '')
            .toString()
            .trim();
        final resolvedCounselor = rawCounselorName.isNotEmpty
            ? rawCounselorName
            : (counselorId.isNotEmpty ? (userIdToName[counselorId] ?? '') : '');

        if (m.className.trim().isNotEmpty && resolvedCounselor.isNotEmpty) {
          classCounselorByClassName[m.className.trim()] = resolvedCounselor;
        }

        classItems.add(
          DocClassItem(
            id: m.id ?? d.id,
            className: m.className,
            classLevel: m.classLevel,
            advisorTeacher: resolvedAdvisor,
          ),
        );
      }
      classItems.sort((a, b) {
        final cmp = a.classLevel.compareTo(b.classLevel);
        return cmp != 0 ? cmp : a.className.compareTo(b.className);
      });
    } catch (_) {}

    // 6. ŞÖK & Sınıf Bazlı TAM Ders Öğretmenleri Birleştiricisi
    // (lessonAssignments + courseGroups kurlu dersler + classSchedules haftalık program + Şube Rehber + Sınıf PDR)
    final Map<String, Map<String, String>> classTeacherDisplayByNorm = {};
    final Map<String, Map<String, List<String>>> classTeacherRolesByNorm = {};

    bool isSyntheticTeacherPlaceholder(String raw) {
      final n = _normTr(raw);
      return n.isEmpty ||
          n == '-' ||
          n == 'ogretmen' ||
          n == 'öğretmen' ||
          n.startsWith('kur:') ||
          n.startsWith('kulup:') ||
          n.startsWith('kulüp:');
    }

    void addClassTeacher(String clsName, String rawTeacherName, String rawRole) {
      final cleanCls = clsName.trim();
      final cleanTeacher = rawTeacherName.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleanCls.isEmpty || isSyntheticTeacherPlaceholder(cleanTeacher)) return;

      final tKey = _personDedupKey(cleanTeacher);
      if (tKey.isEmpty) return;

      final displayMap = classTeacherDisplayByNorm.putIfAbsent(cleanCls, () => {});
      final existingDisplay = displayMap[tKey];
      if (existingDisplay == null ||
          _turkishCharScore(cleanTeacher) > _turkishCharScore(existingDisplay)) {
        displayMap[tKey] = cleanTeacher;
      }

      final rolesMap = classTeacherRolesByNorm.putIfAbsent(cleanCls, () => {});
      final roles = rolesMap.putIfAbsent(tKey, () => []);
      final cleanRole = rawRole.trim();
      if (cleanRole.isNotEmpty && cleanRole != '-') {
        final rKey = _personDedupKey(cleanRole);
        final existingIdx = roles.indexWhere((existing) => _personDedupKey(existing) == rKey);
        if (existingIdx == -1) {
          roles.add(cleanRole);
        } else if (_turkishCharScore(cleanRole) > _turkishCharScore(roles[existingIdx])) {
          roles[existingIdx] = cleanRole;
        }
      }
    }

    void addTeachersFromIdsAndNames(
      String clsName,
      Iterable<dynamic> tIds,
      Iterable<dynamic> tNames,
      String lessonLabel,
    ) {
      for (final rawId in tIds) {
        final tid = rawId.toString().trim();
        if (tid.isEmpty) continue;
        final resolvedName = userIdToName[tid];
        if (resolvedName != null && resolvedName.isNotEmpty) {
          final roleLabel = lessonLabel.trim().isNotEmpty
              ? lessonLabel.trim()
              : (userIdToBranch[tid] ?? '');
          addClassTeacher(clsName, resolvedName, roleLabel);
        }
      }
      for (final rawName in tNames) {
        final str = rawName.toString().trim();
        if (str.isEmpty) continue;
        // Bazı kayıtlarda tek string içinde virgülle birden fazla öğretmen adı bulunabilir
        final parts = str.contains(',') ? str.split(',') : <String>[str];
        for (final p in parts) {
          addClassTeacher(clsName, p, lessonLabel);
        }
      }
    }

    // 6.1. lessonAssignments üzerinden şube ders öğretmenleri
    final bool hasTermScopedAssignments = activeTermId.isNotEmpty &&
        rawAssignments.any((d) {
          final docStId = (d['schoolTypeId'] ?? '').toString().trim();
          final matchesType =
              schoolTypeId.isEmpty || docStId.isEmpty || docStId == schoolTypeId;
          return matchesType && (d['termId'] ?? '').toString().trim() == activeTermId;
        });

    for (final d in rawAssignments) {
      final docStId = (d['schoolTypeId'] ?? '').toString().trim();
      if (schoolTypeId.isNotEmpty && docStId.isNotEmpty && docStId != schoolTypeId) {
        continue;
      }
      if (hasTermScopedAssignments) {
        final rowTerm = (d['termId'] ?? '').toString().trim();
        if (rowTerm.isNotEmpty && rowTerm != activeTermId) continue;
      }

      final clsId = (d['classId'] ?? '').toString().trim();
      final clsName = classIdToName[clsId] ?? (d['className'] ?? '').toString().trim();
      if (clsName.isEmpty) continue;
      if (schoolTypeId.isNotEmpty &&
          docStId.isEmpty &&
          knownClassNames.isNotEmpty &&
          !knownClassNames.contains(clsName)) {
        continue;
      }

      final lessonName = (d['lessonName'] ?? '').toString().trim();
      final List<dynamic> tIds = [
        if (d['teacherIds'] is Iterable) ...(d['teacherIds'] as Iterable),
        if (d['teacherId'] != null) d['teacherId'],
      ];
      final List<dynamic> tNames = [
        if (d['teacherNames'] is Iterable) ...(d['teacherNames'] as Iterable),
        if (d['teacherName'] != null) d['teacherName'],
      ];
      addTeachersFromIdsAndNames(clsName, tIds, tNames, lessonName);
    }

    // 6.2. Kurlu Ders Grupları (courseGroups - örn. İngilizce, Almanca seviye kurları)
    // Şubedeki öğrencilerin kayıtlı olduğu kur alt gruplarının (subGroups) öğretmenlerini şubeye ekler!
    final relevantTrackGroups = rawTrackGroups.where((d) {
      final docStId = (d['schoolTypeId'] ?? '').toString().trim();
      if (schoolTypeId.isNotEmpty && docStId.isNotEmpty && docStId != schoolTypeId) {
        return false;
      }
      return true;
    }).toList();

    final bool hasTermScopedTracks = activeTermId.isNotEmpty &&
        relevantTrackGroups.any(
          (d) => (d['termId'] ?? '').toString().trim() == activeTermId,
        );

    if (relevantTrackGroups.isNotEmpty) {
      final Map<String, String> studentIdToClassName = {};
      try {
        final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
        final stSnap = await _db
            .collection('students')
            .where('institutionId', whereIn: instFilter)
            .where('isActive', isEqualTo: true)
            .get();
        for (final sDoc in stSnap.docs) {
          final sd = sDoc.data();
          final sClsId = (sd['classId'] ?? '').toString().trim();
          final sClsName =
              classIdToName[sClsId] ?? (sd['className'] ?? '').toString().trim();
          if (sClsName.isEmpty) continue;
          if (knownClassNames.isNotEmpty && !knownClassNames.contains(sClsName)) {
            continue;
          }
          studentIdToClassName[sDoc.id] = sClsName;
        }
      } catch (_) {}

      for (final g in relevantTrackGroups) {
        if (hasTermScopedTracks) {
          final rowTerm = (g['termId'] ?? '').toString().trim();
          if (rowTerm.isNotEmpty && rowTerm != activeTermId) continue;
        }

        final lessonLabel = (g['lessonName'] ?? '').toString().trim().isNotEmpty
            ? (g['lessonName'] ?? '').toString().trim()
            : (g['name'] ?? 'Kurlu Ders').toString().trim();
        final subGroups = g['subGroups'] is List ? (g['subGroups'] as List) : const [];

        bool anyStudentAssignedInGroup = false;
        for (final sg in subGroups) {
          if (sg is Map &&
              sg['studentIds'] is Iterable &&
              (sg['studentIds'] as Iterable).isNotEmpty) {
            anyStudentAssignedInGroup = true;
            break;
          }
        }

        // Grup düzeyinde hedef şubeler (öğrenci dağıtımı henüz yapılmamış kurlar için yedek)
        final Set<String> groupTargetClasses = {};
        if (g['targetClassIds'] is Iterable) {
          for (final cid in (g['targetClassIds'] as Iterable)) {
            final cname = classIdToName[cid.toString().trim()];
            if (cname != null && cname.isNotEmpty) groupTargetClasses.add(cname);
          }
        }
        if (g['targetClassNames'] is Iterable) {
          for (final cn in (g['targetClassNames'] as Iterable)) {
            final s = cn.toString().trim();
            if (s.isNotEmpty &&
                (knownClassNames.isEmpty || knownClassNames.contains(s))) {
              groupTargetClasses.add(s);
            }
          }
        }
        if (groupTargetClasses.isEmpty && g['targetGradeLevels'] is Iterable) {
          for (final lvl in (g['targetGradeLevels'] as Iterable)) {
            final parsed = lvl is int ? lvl : int.tryParse(lvl.toString());
            if (parsed != null && classLevelToNames.containsKey(parsed)) {
              groupTargetClasses.addAll(classLevelToNames[parsed]!);
            }
          }
        }

        for (final sg in subGroups) {
          if (sg is! Map) continue;
          final sgTeacherIds = sg['teacherIds'] is Iterable
              ? (sg['teacherIds'] as Iterable)
              : const [];
          final sgTeacherNames = sg['teacherNames'] is Iterable
              ? (sg['teacherNames'] as Iterable)
              : const [];

          final Set<String> matchedClassesForSubGroup = {};
          if (sg['studentIds'] is Iterable) {
            for (final sid in (sg['studentIds'] as Iterable)) {
              final clsName = studentIdToClassName[sid.toString().trim()];
              if (clsName != null && clsName.isNotEmpty) {
                matchedClassesForSubGroup.add(clsName);
              }
            }
          }

          if (matchedClassesForSubGroup.isEmpty && !anyStudentAssignedInGroup) {
            matchedClassesForSubGroup.addAll(groupTargetClasses);
          }

          for (final clsName in matchedClassesForSubGroup) {
            addTeachersFromIdsAndNames(
              clsName,
              sgTeacherIds,
              sgTeacherNames,
              lessonLabel,
            );
          }
        }
      }
    }

    // 6.3. Haftalık Ders Programı (classSchedules) üzerinden ek ders öğretmenleri
    try {
      final instFilter = instVariants.isNotEmpty ? instVariants : [institutionId];
      Query<Map<String, dynamic>> wpQuery = _db
          .collection('workPeriods')
          .where('institutionId', whereIn: instFilter)
          .where('isActive', isEqualTo: true);
      if (schoolTypeId.isNotEmpty) {
        wpQuery = wpQuery.where('schoolTypeId', isEqualTo: schoolTypeId);
      }
      final wpSnap = await wpQuery.get();
      final List<String> activePeriodIds = [];
      for (final doc in wpSnap.docs) {
        final d = doc.data();
        if (d['schedulePublished'] == true) {
          activePeriodIds.insert(0, doc.id);
        } else {
          activePeriodIds.add(doc.id);
        }
      }

      QuerySnapshot<Map<String, dynamic>>? schedSnap;
      if (activePeriodIds.isNotEmpty) {
        schedSnap = await _db
            .collection('classSchedules')
            .where('periodId', whereIn: activePeriodIds.take(10).toList())
            .get();
      } else {
        schedSnap = await _db
            .collection('classSchedules')
            .where('institutionId', whereIn: instFilter)
            .where('isActive', isEqualTo: true)
            .get();
      }

      for (final doc in schedSnap.docs) {
        final d = doc.data();
        if (d['isActive'] == false) continue;
        final clsId = (d['classId'] ?? '').toString().trim();
        final clsName = classIdToName[clsId] ?? (d['className'] ?? '').toString().trim();
        if (clsName.isEmpty) continue;
        if (knownClassNames.isNotEmpty && !knownClassNames.contains(clsName)) {
          continue;
        }
        final lessonName =
            (d['lessonName'] ?? d['subjectName'] ?? '').toString().trim();
        if (_normTr(lessonName).startsWith('kulup') ||
            _normTr(lessonName).startsWith('kulüp')) {
          continue;
        }
        final List<dynamic> tIds = [
          if (d['teacherIds'] is Iterable) ...(d['teacherIds'] as Iterable),
          if (d['teacherId'] != null) d['teacherId'],
        ];
        final List<dynamic> tNames = [
          if (d['teacherNames'] is Iterable) ...(d['teacherNames'] as Iterable),
          if (d['teacherName'] != null) d['teacherName'],
        ];
        addTeachersFromIdsAndNames(clsName, tIds, tNames, lessonName);
      }
    } catch (_) {}

    // 6.4. Şube Rehber Öğretmeni ve Sınıf Rehber/PDR Öğretmeni
    for (final cls in classItems) {
      if (cls.advisorTeacher.trim().isNotEmpty) {
        addClassTeacher(cls.className, cls.advisorTeacher, 'Şube Rehber Öğrt.');
      }
      final specificCounselor = classCounselorByClassName[cls.className];
      if (specificCounselor != null && specificCounselor.isNotEmpty) {
        addClassTeacher(
          cls.className,
          specificCounselor,
          'Rehberlik ve Psikolojik Danışmanlık',
        );
      } else if (counselors.length == 1) {
        // Okul türünde tek rehber öğretmen varsa tüm şubelerin ŞÖK doğal üyesidir
        addClassTeacher(
          cls.className,
          counselors.first.fullName,
          'Rehberlik ve Psikolojik Danışmanlık',
        );
      }
    }

    // 6.5. Tüm şubeler için alfabetik ve tekilleştirilmiş "AD SOYAD (Branş)" listesini oluştur
    classTeacherDisplayByNorm.forEach((clsName, normToDisplay) {
      final rolesMap = classTeacherRolesByNorm[clsName] ?? const {};
      final entries = normToDisplay.entries.toList()
        ..sort((a, b) => _turkishCompare(a.value, b.value));

      classTeachersByClass[clsName] = entries.map((e) {
        final name = e.value;
        final roles = rolesMap[e.key] ?? const [];
        if (roles.isEmpty) return name;
        return '$name (${roles.join(" / ")})';
      }).toList();
    });

    final defaultBranches = <String>[
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'T.C. İnkılap Tarihi ve Atatürkçülük',
      'Yabancı Dil (İngilizce)',
      'Din Kültürü ve Ahlak Bilgisi',
      'Görsel Sanatlar',
      'Müzik',
      'Beden Eğitimi ve Spor',
      'Bilişim Teknolojileri ve Yazılım',
      'Rehberlik ve Psikolojik Danışmanlık',
    ];
    for (final b in defaultBranches) {
      branchSet.add(b);
    }
    final sortedBranches = branchSet.toList()..sort(_turkishCompare);

    final ctx = SchoolDocContext(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      schoolName: schoolName.isNotEmpty ? schoolName : 'Okul Müdürlüğü',
      schoolTypeName: schoolTypeName,
      city: city,
      district: district,
      address: address,
      phone: phone,
      email: email,
      logoUrl: logoUrl,
      academicYear: academicYear,
      activeTermLabel: activeTermLabel,
      principalName: principalName,
      vicePrincipals: vicePrincipals,
      counselors: counselors,
      allStaff: allStaff,
      classes: classItems,
      branches: sortedBranches,
      classTeachersByClass: classTeachersByClass,
      currentUser: currentUserItem,
    );

    _contextCache[cacheKey] = ctx;
    _contextCacheTime[cacheKey] = DateTime.now();
    return ctx;
  }

  /// Seçilen sınıf/şube listesi için aktif öğrencileri (numara/ad-soyad sıralı) getirir
  Future<List<DocStudentItem>> loadStudentsForClasses({
    required String institutionId,
    required List<DocClassItem> targetClasses,
  }) async {
    if (targetClasses.isEmpty) return [];
    final List<DocStudentItem> result = [];
    final Set<String> seenIds = {};

    for (final cls in targetClasses) {
      QuerySnapshot snap = await _db
          .collection('students')
          .where('institutionId', isEqualTo: institutionId)
          .where('classId', isEqualTo: cls.id)
          .get();

      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('students')
            .where('institutionId', isEqualTo: institutionId)
            .where('className', isEqualTo: cls.className)
            .get();
      }

      for (final doc in snap.docs) {
        if (seenIds.contains(doc.id)) continue;
        final d = doc.data() as Map<String, dynamic>;
        final status = (d['status'] ?? '').toString().toLowerCase();
        if (d['isActive'] == false || status == 'passive' || status == 'pasif' || status == 'inactive') {
          continue;
        }

        final first = (d['firstName'] ?? d['name'] ?? '').toString().trim();
        final last = (d['lastName'] ?? d['surname'] ?? '').toString().trim();
        String fullName = (d['fullName'] ?? '$first $last').toString().trim();
        if (fullName.isEmpty) continue;

        final studentNo = (d['studentNumber'] ?? d['schoolNumber'] ?? d['studentNo'] ?? d['no'] ?? '').toString().trim();
        final tcNo = (d['tcNo'] ?? d['tc'] ?? d['tcKimlikNo'] ?? d['identityNumber'] ?? '').toString().trim();
        final parentName = (d['parentName'] ??
                d['guardianName'] ??
                d['fatherName'] ??
                d['motherName'] ??
                d['veliAdi'] ??
                '')
            .toString()
            .trim();
        final parentPhone = (d['parentPhone'] ??
                d['guardianPhone'] ??
                d['fatherPhone'] ??
                d['motherPhone'] ??
                d['phone'] ??
                '')
            .toString()
            .trim();

        seenIds.add(doc.id);
        result.add(
          DocStudentItem(
            id: doc.id,
            fullName: fullName,
            studentNo: studentNo,
            tcNo: tcNo,
            className: cls.className,
            parentName: parentName,
            parentPhone: parentPhone,
          ),
        );
      }
    }

    result.sort((a, b) {
      final clsCmp = a.className.compareTo(b.className);
      if (clsCmp != 0) return clsCmp;
      final nA = int.tryParse(a.studentNo);
      final nB = int.tryParse(b.studentNo);
      if (nA != null && nB != null) return nA.compareTo(nB);
      return a.fullName.compareTo(b.fullName);
    });

    return result;
  }

  // ─────────────────── ARŞİV / KAYITLI RESMİ EVRAKLAR ───────────────────
  // Not: Canlı Firestore kurallarında `institutions/{instId}/{allSubcollections=**}`
  // otomatik okuma/yazma iznine sahip olduğu için kurum alt koleksiyonu kullanılır.

  CollectionReference<Map<String, dynamic>> _docsRef(String institutionId) {
    final safeInstId = institutionId.trim().isNotEmpty ? institutionId.trim() : 'default';
    return _db.collection('institutions').doc(safeInstId).collection('official_documents');
  }

  Future<String> saveDocument(SavedOfficialDocument doc) async {
    final col = _docsRef(doc.institutionId);
    final ref = doc.id.isEmpty ? col.doc() : col.doc(doc.id);
    await ref.set(doc.toMap(), SetOptions(merge: true));
    return ref.id;
  }

  Stream<List<SavedOfficialDocument>> streamDocuments({
    required String institutionId,
    required String schoolTypeId,
    bool onlyCreatedByMe = false,
    String? currentUserId,
  }) {
    if (institutionId.trim().isEmpty) {
      return Stream.value(const <SavedOfficialDocument>[]);
    }
    return _docsRef(institutionId).snapshots().map((snap) {
      var list = snap.docs
          .map((d) => SavedOfficialDocument.fromMap(d.data(), d.id))
          .where((d) => d.isActive)
          .toList();

      if (schoolTypeId.isNotEmpty) {
        list = list.where((d) => d.schoolTypeId.isEmpty || d.schoolTypeId == schoolTypeId).toList();
      }
      if (onlyCreatedByMe && currentUserId != null && currentUserId.isNotEmpty) {
        list = list.where((d) => d.createdBy == currentUserId).toList();
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> setDocumentPassive(String institutionId, String id, bool isPassive) async {
    await _docsRef(institutionId).doc(id).update({
      'isPassive': isPassive,
    });
  }

  Future<void> deleteDocument(String institutionId, String id) async {
    await _docsRef(institutionId).doc(id).update({
      'isActive': false,
    });
  }
}

