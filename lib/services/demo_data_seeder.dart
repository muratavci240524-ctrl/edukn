import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/school_type_modules.dart';
import 'crypto_service.dart';
import 'demo_seed/demo_seed_all.dart';
import 'demo_seed/demo_seed_context.dart';
import 'demo_seed/demo_seed_registry.dart';

/// Demo veri üretiminin sonucu.
class DemoSeedResult {
  final Map<String, int> counts;
  final int totalDocs;
  final List<String> notes;

  const DemoSeedResult({
    required this.counts,
    required this.totalDocs,
    this.notes = const [],
  });
}

/// Tanıtım / demo amaçlı: Bir kuruma (institutionId) bağlı tüm sistemi
/// gerçekçi sahte verilerle doldurur.
///
/// GÜVENLİK:
///  * Üretilen HER doküman `isDemo: true` ve `demoTag` alanı taşır.
///  * Kurumda gerçek (isDemo olmayan) öğrenci varsa üretim REDDEDİLİR.
///  * [clear] yalnızca `isDemo == true` olan dokümanları siler.
class DemoDataSeeder {
  DemoDataSeeder._();

  static const String demoTag = 'edukn_demo_v1';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// institutionId filtresi + isDemo filtresiyle temizlenen üst düzey koleksiyonlar.
  static const List<String> _topCollections = [
    'students',
    'parents',
    'users',
    'classes',
    'classTypes',
    'lessons',
    'branches',
    'lessonAssignments',
    'homeworks',
    'class_exams',
    'trial_exams',
    'exam_types',
    'lessonAttendance',
    'etut_requests',
    'schoolTypes',
    'terms',
  ];

  static String _p = 'demo_';
  static String _prefixFor(String inst) => 'd${_slug(inst)}_';

  static List<String> get _demoMealPeriodIds => [
    '${_p}meal_breakfast',
    '${_p}meal_lunch',
    '${_p}meal_snack',
  ];

  // ───────────────────────── İsim havuzları ─────────────────────────
  static const List<String> _female = [
    'Zeynep',
    'Elif',
    'Defne',
    'Ecrin',
    'Asya',
    'Azra',
    'Nehir',
    'Ada',
    'Mira',
    'Ayşe',
    'Hira',
    'Melisa',
    'İpek',
    'Duru',
    'Sude',
    'Beren',
    'Lina',
    'Eylül',
    'Nisa',
    'Rabia',
    'Ceren',
    'Selin',
    'Yaren',
    'Buse',
  ];
  static const List<String> _male = [
    'Yusuf',
    'Alparslan',
    'Mustafa',
    'Eymen',
    'Kerem',
    'Ömer',
    'Ahmet',
    'Çınar',
    'Arda',
    'Emir',
    'Kuzey',
    'Poyraz',
    'Efe',
    'Berat',
    'Mert',
    'Hamza',
    'Burak',
    'Doruk',
    'Deniz',
    'Aras',
    'Toprak',
    'Atlas',
    'Barış',
    'Can',
  ];
  static const List<String> _surnames = [
    'Yılmaz',
    'Kaya',
    'Demir',
    'Şahin',
    'Çelik',
    'Yıldız',
    'Yıldırım',
    'Öztürk',
    'Aydın',
    'Özdemir',
    'Arslan',
    'Doğan',
    'Kılıç',
    'Aslan',
    'Çetin',
    'Kara',
    'Koç',
    'Kurt',
    'Özkan',
    'Şimşek',
    'Polat',
    'Korkmaz',
    'Güneş',
    'Erdem',
    'Aksoy',
    'Tekin',
    'Bulut',
    'Acar',
    'Türkmen',
    'Bozkurt',
  ];

  // ───────────────────────── Ders tanımları ─────────────────────────
  static const List<_LessonDef> _ortaokulLessons = [
    _LessonDef('Türkçe', 'TÜR', 5, 'Türkçe'),
    _LessonDef('Matematik', 'MAT', 5, 'Matematik'),
    _LessonDef('Fen Bilimleri', 'FEN', 4, 'Fen Bilimleri'),
    _LessonDef('Sosyal Bilgiler', 'SOS', 3, 'Sosyal Bilgiler'),
    _LessonDef('İngilizce', 'İNG', 3, 'İngilizce'),
    _LessonDef('Din Kültürü ve Ahlak Bilgisi', 'DİN', 2, 'Din Kültürü'),
    _LessonDef('Beden Eğitimi ve Spor', 'BED', 2, 'Beden Eğitimi'),
    _LessonDef('Görsel Sanatlar', 'GÖR', 1, 'Görsel Sanatlar'),
    _LessonDef('Müzik', 'MÜZ', 1, 'Müzik'),
  ];
  static const List<_LessonDef> _liseLessons = [
    _LessonDef('Türk Dili ve Edebiyatı', 'EDB', 5, 'Edebiyat'),
    _LessonDef('Matematik', 'MAT', 6, 'Matematik'),
    _LessonDef('Fizik', 'FİZ', 3, 'Fizik'),
    _LessonDef('Kimya', 'KİM', 3, 'Kimya'),
    _LessonDef('Biyoloji', 'BİY', 3, 'Biyoloji'),
    _LessonDef('Tarih', 'TAR', 2, 'Tarih'),
    _LessonDef('Coğrafya', 'COĞ', 2, 'Coğrafya'),
    _LessonDef('İngilizce', 'İNG', 4, 'İngilizce'),
    _LessonDef('Din Kültürü ve Ahlak Bilgisi', 'DİN', 2, 'Din Kültürü'),
    _LessonDef('Beden Eğitimi ve Spor', 'BED', 2, 'Beden Eğitimi'),
  ];
  static const List<_LessonDef> _anaokuluLessons = [
    _LessonDef('Türkçe Dil Etkinliği', 'TDE', 5, 'Okul Öncesi'),
    _LessonDef('Matematik Etkinliği', 'MAT', 4, 'Okul Öncesi'),
    _LessonDef('Fen ve Doğa Etkinliği', 'FEN', 3, 'Okul Öncesi'),
    _LessonDef('Sanat Etkinliği', 'SAN', 3, 'Okul Öncesi'),
    _LessonDef('Müzik Etkinliği', 'MÜZ', 2, 'Müzik'),
    _LessonDef('Oyun ve Hareket', 'OYN', 4, 'Beden Eğitimi'),
    _LessonDef('İngilizce', 'İNG', 2, 'İngilizce'),
    _LessonDef('Drama', 'DRM', 2, 'Okul Öncesi'),
  ];
  static const List<_LessonDef> _ilkokulLessons = [
    _LessonDef('Türkçe', 'TÜR', 6, 'Türkçe'),
    _LessonDef('Matematik', 'MAT', 5, 'Matematik'),
    _LessonDef('Hayat Bilgisi', 'HAY', 3, 'Hayat Bilgisi'),
    _LessonDef('Fen Bilimleri', 'FEN', 3, 'Fen Bilimleri'),
    _LessonDef('İngilizce', 'İNG', 2, 'İngilizce'),
    _LessonDef('Görsel Sanatlar', 'GÖR', 1, 'Görsel Sanatlar'),
    _LessonDef('Müzik', 'MÜZ', 1, 'Müzik'),
    _LessonDef('Beden Eğitimi ve Oyun', 'BED', 2, 'Beden Eğitimi'),
  ];

  // ───────────────────────── Sınav türleri ─────────────────────────
  static const List<_SubjectDef> _lgsSubjects = [
    _SubjectDef('Türkçe', 20, 4.348),
    _SubjectDef('Matematik', 20, 4.254),
    _SubjectDef('Fen Bilimleri', 20, 4.123),
    _SubjectDef('T.C. İnkılap Tarihi ve Atatürkçülük', 10, 1.666),
    _SubjectDef('Din Kültürü ve Ahlak Bilgisi', 10, 1.899),
    _SubjectDef('Yabancı Dil', 10, 1.508),
  ];
  static const List<_SubjectDef> _tytSubjects = [
    _SubjectDef('TYT Türkçe', 40, 3.30),
    _SubjectDef('TYT Sosyal Bilimler', 20, 3.40),
    _SubjectDef('TYT Temel Matematik', 40, 3.30),
    _SubjectDef('TYT Fen Bilimleri', 20, 3.40),
  ];
  static const List<_SubjectDef> _genelOrtaokulSubjects = [
    _SubjectDef('Türkçe', 15, 1.0),
    _SubjectDef('Matematik', 15, 1.0),
    _SubjectDef('Fen Bilimleri', 15, 1.0),
    _SubjectDef('Sosyal Bilgiler', 10, 1.0),
    _SubjectDef('Yabancı Dil', 10, 1.0),
  ];

  // ═════════════════════════════ ÜRET ═════════════════════════════
  static Future<DemoSeedResult> seed({
    required String institutionId,
    void Function(String message, double progress)? onProgress,
  }) async {
    final inst = institutionId.trim();
    if (inst.isEmpty) {
      throw StateError('Kurum (institutionId) bulunamadı.');
    }
    _p = _prefixFor(inst);
    void report(String m, double p) => onProgress?.call(m, p);

    report('Güvenlik kontrolü yapılıyor...', 0.01);
    final existingStudents = await _db
        .collection('students')
        .where('institutionId', isEqualTo: inst)
        .limit(40)
        .get();
    final hasReal = existingStudents.docs.any(
      (d) => d.data()['isDemo'] != true,
    );
    if (hasReal) {
      throw StateError(
        'Bu kurumda GERÇEK öğrenci kayıtları var. Demo verisi yalnızca boş / '
        'demo amaçlı açılmış hesaplarda üretilebilir.',
      );
    }

    report('Önceki demo verileri temizleniyor...', 0.03);
    await clear(institutionId: inst);

    if (!CryptoService.isInitialized) {
      try {
        await CryptoService.init().timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('[DemoSeeder] CryptoService.init atlandı: $e');
      }
    }

    final rng = math.Random(20261103);
    final w = DemoBatchWriter(_db);
    final counts = <String, int>{};
    final notes = <String>[];
    void count(String k, [int n = 1]) => counts[k] = (counts[k] ?? 0) + n;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ── 1. Dönem ────────────────────────────────────────────────────
    report('Dönem hazırlanıyor...', 0.05);
    String termId = '';
    final termsSnap = await _db
        .collection('terms')
        .where('institutionId', isEqualTo: inst)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? activeTermDoc;
    for (final d in termsSnap.docs) {
      if (d.data()['isActive'] == true) {
        activeTermDoc = d;
        break;
      }
    }
    activeTermDoc ??= termsSnap.docs.isNotEmpty ? termsSnap.docs.first : null;

    int startYear = today.month >= 9 ? today.year : today.year - 1;
    if (activeTermDoc != null) {
      termId = activeTermDoc.id;
      startYear =
          int.tryParse('${activeTermDoc.data()['startYear']}') ?? startYear;
    } else {
      termId = '${_p}term_$startYear';
      await w.set(_db.collection('terms').doc(termId), {
        'institutionId': inst,
        'name': '$startYear-${startYear + 1}',
        'termName': '$startYear-${startYear + 1}',
        'startYear': startYear,
        'endYear': startYear + 1,
        'isActive': true,
        'subTerms': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        ..._demoFlag(inst),
      });
      count('Dönem');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_term_id', termId);
        await prefs.setString('selected_term_id', termId);
      } catch (_) {}
      notes.add('Yeni dönem oluşturuldu: $startYear-${startYear + 1}');
    }
    final termStart = DateTime(startYear, 9, 1);

    // ── 2. Okul türleri ────────────────────────────────────────────
    report('Okul türleri hazırlanıyor...', 0.07);
    final stSnap = await _db
        .collection('schoolTypes')
        .where('institutionId', isEqualTo: inst)
        .get();
    final List<DemoTypeDef> types = [];
    for (final d in stSnap.docs) {
      final data = d.data();
      if (data['isActive'] == false) continue;
      final kind = (data['schoolType'] ?? '').toString();
      final levels = _levelsFor(kind, data['activeGrades']);
      if (levels.isEmpty) continue;
      types.add(
        DemoTypeDef(
          id: d.id,
          kind: kind,
          name: (data['schoolTypeName'] ?? kind).toString(),
          levels: levels,
        ),
      );
    }
    if (types.length < 4) {
      final allModules = SchoolTypeModules.allModuleKeys;
      const defs = [
        ['Anaokulu', 'Anaokulu', '3 Yaş|4 Yaş|5 Yaş'],
        ['İlkokul', 'İlkokul', '1. Sınıf|2. Sınıf|3. Sınıf|4. Sınıf'],
        ['Ortaokul', 'Ortaokul', '5. Sınıf|6. Sınıf|7. Sınıf|8. Sınıf'],
        ['Lise', 'Lise', '9. Sınıf|10. Sınıf|11. Sınıf|12. Sınıf'],
      ];
      for (final def in defs) {
        if (types.any((t) => t.kind == def[0])) continue;
        final id = '${_p}st_${_slug(def[0])}';
        await w.set(_db.collection('schoolTypes').doc(id), {
          'institutionId': inst,
          'schoolType': def[0],
          'schoolTypeName': def[1],
          'capacity': 600,
          'activeModules': allModules,
          'activeGrades': def[2].split('|'),
          'studentCount': 0,
          'teacherCount': 0,
          'classCount': 0,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          ..._demoFlag(inst),
        });
        types.add(
          DemoTypeDef(
            id: id,
            kind: def[0],
            name: def[1],
            levels: _levelsFor(def[0], def[2].split('|')),
          ),
        );
        count('Okul Türü');
      }
      notes.add(
        'Eksik okul türleri (Anaokulu, İlkokul, Ortaokul, Lise) demo olarak oluşturuldu.',
      );
    }

    // ── 3. Sınıf tipi ──────────────────────────────────────────────
    String classTypeId = '';
    String classTypeName = 'Ders Sınıfı';
    final ctSnap = await _db
        .collection('classTypes')
        .where('institutionId', isEqualTo: inst)
        .limit(5)
        .get();
    if (ctSnap.docs.isNotEmpty) {
      final pick = ctSnap.docs.firstWhere(
        (d) => d.data()['isDefault'] == true,
        orElse: () => ctSnap.docs.first,
      );
      classTypeId = pick.id;
      classTypeName = (pick.data()['typeName'] ?? classTypeName).toString();
    } else {
      classTypeId = '${_p}classtype_default';
      await w.set(_db.collection('classTypes').doc(classTypeId), {
        'typeName': classTypeName,
        'description': 'Demo varsayılan sınıf tipi',
        'institutionId': inst,
        'createdAt': Timestamp.fromDate(now),
        'isDefault': true,
        ..._demoFlag(inst),
      });
      count('Sınıf Tipi');
    }

    // ── 4. Her okul türü için yapı ─────────────────────────────────
    int studentCounter = 100;
    int globalNameIdx = 0;
    final List<DemoClassInfo> allClasses = [];
    final List<DemoTeacherInfo> teacherInfos = [];
    final Map<String, List<DemoStudentInfo>> studentsByClass = {};
    final Map<String, List<DemoStudentInfo>> studentsByTypeLevel = {};
    final Map<String, DemoLessonInfo> lessonInfoById = {};

    final schoolDocId = await _resolveSchoolDocId(inst);

    for (int ti = 0; ti < types.length; ti++) {
      final type = types[ti];
      final typeKey = _slug(type.id).length > 14
          ? _slug(type.id).substring(0, 14)
          : _slug(type.id);
      final lessonDefs = _lessonDefsFor(type.kind);
      final double base = ti / types.length;
      report('${type.name}: dersler ve öğretmenler...', 0.10 + base * 0.55);

      // Dersler + branşlar + öğretmenler
      final List<DemoLessonInfo> lessons = [];
      for (int li = 0; li < lessonDefs.length; li++) {
        final def = lessonDefs[li];
        final slug = _slug(def.name);
        final branchId = '${_p}br_$slug';
        final lessonId = '${_p}ls_${typeKey}_$slug';
        final teacherId = '${_p}tc_${typeKey}_$slug';

        if (ti == 0 || !lessons.any((l) => l.branchId == branchId)) {
          await w.set(_db.collection('branches').doc(branchId), {
            'branchName': def.branch,
            'institutionId': inst,
            'isDefault': false,
            'isActive': true,
            ..._demoFlag(inst),
          });
          count('Branş');
        }

        await w.set(_db.collection('lessons').doc(lessonId), {
          'lessonName': def.name,
          'shortName': def.shortName,
          'branchId': branchId,
          'branchName': def.branch,
          'schoolTypeId': type.id,
          'institutionId': inst,
          'termId': termId,
          'subTermId': '${_p}wp_${type.id}',
          'periodId': '${_p}wp_${type.id}',
          'subTermName': null,
          'periodName': null,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          ..._demoFlag(inst),
        });
        count('Ders');

        final gender = rng.nextBool();
        final first =
            (gender ? _female : _male)[(globalNameIdx * 5 + li * 3) %
                (gender ? _female.length : _male.length)];
        final last =
            _surnames[(globalNameIdx * 7 + li * 11 + 3) % _surnames.length];
        final tName = '$first $last';
        final username = 'ogretmen${ti + 1}${li + 1}';
        await w.set(_db.collection('users').doc(teacherId), {
          'uid': teacherId,
          'institutionId': inst,
          'type': 'staff',
          'title': 'ogretmen',
          'role': 'teacher',
          'fullName': tName,
          'name': first,
          'surname': last,
          'username': username,
          'email': '$username@$inst.edukn'.toLowerCase(),
          'branch': def.branch,
          'workLocations': [type.name],
          'schoolTypeId': type.id,
          'termId': termId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          ..._demoFlag(inst),
        });
        count('Öğretmen');
        globalNameIdx++;

        final info = DemoLessonInfo(
          id: lessonId,
          name: def.name,
          shortName: def.shortName,
          branchId: branchId,
          weeklyHours: def.weeklyHours,
          teacherId: teacherId,
          teacherName: tName,
        );
        lessons.add(info);
        teacherInfos.add(
          DemoTeacherInfo(
            id: teacherId,
            fullName: tName,
            branch: def.branch,
            typeId: type.id,
            typeName: type.name,
          ),
        );
        lessonInfoById[lessonId] = info;
      }

      // Sınıflar / öğrenciler
      for (final level in type.levels) {
        for (final section in const ['A', 'B']) {
          final className = type.kind == 'Anaokulu'
              ? '$level Yaş $section'
              : '$level-$section';
          final classId = '${_p}cl_${typeKey}_$level$section';
          final classTeacher =
              lessons[(level + (section == 'A' ? 0 : 1)) % lessons.length];
          await w.set(_db.collection('classes').doc(classId), {
            'className': className,
            'shortName': '$level$section',
            'classTypeId': classTypeId,
            'classTypeName': classTypeName,
            'classTeacherId': classTeacher.teacherId,
            'classTeacherName': classTeacher.teacherName,
            'guidanceCounselorId': null,
            'guidanceCounselorName': null,
            'classroomId': null,
            'classroomName': null,
            'classLevel': level,
            'description': 'Demo sınıfı',
            'schoolTypeId': type.id,
            'schoolTypeName': type.name,
            'institutionId': inst,
            'termId': termId,
            'createdAt': Timestamp.fromDate(termStart),
            'updatedAt': Timestamp.fromDate(now),
            'isActive': true,
            ..._demoFlag(inst),
          });
          count('Sınıf');
          allClasses.add(
            DemoClassInfo(
              id: classId,
              name: className,
              level: level,
              typeId: type.id,
              typeName: type.name,
              typeKind: type.kind,
              lessons: lessons,
            ),
          );

          // Ders atamaları
          for (final l in lessons) {
            await w.set(
              _db
                  .collection('lessonAssignments')
                  .doc('${_p}la_${classId}_${_slug(l.name)}'),
              {
                'lessonId': l.id,
                'lessonName': l.name,
                'classId': classId,
                'className': className,
                'weeklyHours': l.weeklyHours,
                'teacherIds': [l.teacherId],
                'teacherNames': [l.teacherName],
                'schoolTypeId': type.id,
                'institutionId': inst,
                'termId': termId,
                'subTermId': '${_p}wp_${type.id}',
                'periodId': '${_p}wp_${type.id}',
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
                ..._demoFlag(inst),
              },
            );
            count('Ders Ataması');
          }

          // Öğrenciler
          final int perClass = type.kind == 'Lise'
              ? 11
              : (type.kind == 'Anaokulu' ? 10 : 12);
          final List<DemoStudentInfo> classStudents = [];
          for (int si = 0; si < perClass; si++) {
            studentCounter++;
            final isFemale = (si + level + (section == 'A' ? 0 : 1)) % 2 == 0;
            final first =
                (isFemale ? _female : _male)[(globalNameIdx * 3 + si * 7) %
                    (isFemale ? _female.length : _male.length)];
            final last =
                _surnames[(globalNameIdx * 5 + si * 13 + level) %
                    _surnames.length];
            globalNameIdx++;
            final fullName = '$first $last';
            final no = '$studentCounter';
            final tc =
                '2${(studentCounter * 7919 + 12345678).toString().padLeft(10, '0')}';
            final phone =
                '05${50 + rng.nextInt(9)}${(1000000 + rng.nextInt(8999999))}';
            final studentId = '${_p}s_$no';

            // Başarı seviyesi (şampiyon adayları için üst dilim ayrıldı)
            double ability;
            final roll = rng.nextDouble();
            if (roll < 0.10) {
              ability = 0.88 + rng.nextDouble() * 0.09;
            } else if (roll < 0.35) {
              ability = 0.70 + rng.nextDouble() * 0.16;
            } else if (roll < 0.80) {
              ability = 0.48 + rng.nextDouble() * 0.20;
            } else {
              ability = 0.28 + rng.nextDouble() * 0.18;
            }

            final birthYear = type.kind == 'Anaokulu'
                ? now.year - level
                : now.year - (level + 6);
            final birthDate =
                '${_d2(1 + rng.nextInt(28))}.${_d2(1 + rng.nextInt(12))}.$birthYear';

            final motherFirst =
                _female[(globalNameIdx * 2 + 1) % _female.length];
            final parentTcPlain =
                '3${(studentCounter * 6101 + 98765432).toString().padLeft(10, '0')}';
            final parentTcEnc = parentTcPlain;
            final parentPhoneEnc = phone;
            final parentUsername = 'veli$no';
            final parentsList = [
              {
                'name': motherFirst,
                'surname': last,
                'relation': 'Anne',
                'tcNo': parentTcEnc,
                'phone': parentPhoneEnc,
                'email': '$parentUsername@demo.edukn',
                'username': parentUsername,
                'password': 'demo123',
              },
            ];

            await w.set(_db.collection('students').doc(studentId), {
              'institutionId': inst,
              'schoolTypeId': type.id,
              'schoolTypeName': type.name,
              'studentNo': no,
              'studentNumber': no,
              'name': first,
              'surname': last,
              'fullName': fullName,
              'classLevel': '$level',
              'classId': classId,
              'className': className,
              'termId': termId,
              'subTermId': null,
              'tcNo': tc,
              'phone': parentPhoneEnc,
              'username': 'demo$no',
              'password': 'demo123',
              'birthDate': birthDate,
              'registrationDate': '${startYear}-09-08',
              'previousSchool': '',
              'isSelfGuardian': false,
              'registrationType': 'Yeni Kayıt',
              'entryType': 'Normal',
              'gender': isFemale ? 'Kız' : 'Erkek',
              'email': 'demo$no@demo.edukn',
              'educationType': 'Normal Öğretim',
              'foreignLanguage': 'İngilizce',
              'parents': parentsList,
              'parentTcNos': [parentTcEnc],
              'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              ..._demoFlag(inst),
            });
            count('Öğrenci');

            await w.set(_db.collection('parents').doc('${_p}p_$no'), {
              'tcNo': parentTcEnc,
              'name': motherFirst,
              'surname': last,
              'phone': parentPhoneEnc,
              'email': '$parentUsername@demo.edukn',
              'username': parentUsername,
              'password': 'demo123',
              'institutionId': inst,
              'updatedAt': FieldValue.serverTimestamp(),
              ..._demoFlag(inst),
            });
            count('Veli');

            final info = DemoStudentInfo(
              id: studentId,
              no: no,
              fullName: fullName,
              tc: tc,
              className: className,
              classId: classId,
              level: level,
              ability: ability,
              subjectOffsets: {
                for (int k = 0; k < 8; k++) k: (rng.nextDouble() - 0.5) * 0.18,
              },
            );
            classStudents.add(info);
            studentsByTypeLevel
                .putIfAbsent('${type.id}|$level', () => [])
                .add(info);
          }
          studentsByClass[classId] = classStudents;
        }
      }
    }
    await w.flush();

    // ── 5. Ödevler ──────────────────────────────────────────────────
    report('Ödevler üretiliyor...', 0.62);
    for (final c in allClasses) {
      if (c.typeKind == 'Anaokulu') continue;
      final students = studentsByClass[c.id] ?? const [];
      final core = c.lessons.take(4).toList();
      for (int li = 0; li < core.length; li++) {
        final l = core[li];
        for (int hi = 0; hi < 3; hi++) {
          final assigned = today.subtract(Duration(days: 24 - hi * 9 - li));
          final due = assigned.add(const Duration(days: 4));
          final isFuture = due.isAfter(today);
          final statuses = <String, int>{};
          for (final s in students) {
            if (isFuture) {
              statuses[s.id] = 0;
              continue;
            }
            final r = rng.nextDouble() + (0.5 - s.ability) * 0.35;
            if (r < 0.62) {
              statuses[s.id] = 1;
            } else if (r < 0.78) {
              statuses[s.id] = 3;
            } else if (r < 0.90) {
              statuses[s.id] = 2;
            } else {
              statuses[s.id] = 4;
            }
          }
          await w.set(
            _db.collection('homeworks').doc('${_p}hw_${c.id}_${li}_$hi'),
            {
              'id': '${_p}hw_${c.id}_${li}_$hi',
              'institutionId': inst,
              'classId': c.id,
              'className': c.name,
              'lessonId': l.id,
              'lessonName': l.name,
              'teacherId': l.teacherId,
              'title': _hwTitle(l.name, hi),
              'content':
                  'Konu tekrarı ve ilgili sayfalardaki soruları çözünüz.',
              'createdAt': Timestamp.fromDate(assigned),
              'assignedDate': Timestamp.fromDate(assigned),
              'dueDate': Timestamp.fromDate(due),
              'attachments': [],
              'targetStudentIds': [],
              'studentStatuses': statuses,
              'termId': termId,
              'schoolTypeId': c.typeId,
              ..._demoFlag(inst),
            },
          );
          count('Ödev');
        }
      }
    }
    await w.flush();

    // ── 6. Yazılı sınavlar ─────────────────────────────────────────
    report('Yazılı sınavlar ve notlar üretiliyor...', 0.68);
    for (final c in allClasses) {
      if (c.typeKind == 'Anaokulu') continue;
      final students = studentsByClass[c.id] ?? const [];
      final core = c.lessons.take(5).toList();
      for (int li = 0; li < core.length; li++) {
        final l = core[li];
        for (int ei = 0; ei < 2; ei++) {
          final date = today.subtract(
            Duration(days: ei == 0 ? 38 - li : 11 - li),
          );
          final grades = <String, dynamic>{};
          for (final s in students) {
            final off = s.subjectOffsets[li % 8] ?? 0.0;
            final raw =
                (s.ability +
                    off +
                    (rng.nextDouble() - 0.5) * 0.14 +
                    ei * 0.02) *
                100;
            grades[s.id] = (raw.round().clamp(18, 100) / 5).round() * 5;
          }
          await w.set(
            _db.collection('class_exams').doc('${_p}ce_${c.id}_${li}_$ei'),
            {
              'institutionId': inst,
              'classId': c.id,
              'className': c.name,
              'lessonId': l.id,
              'lessonName': l.name,
              'examName': '${ei + 1}. Yazılı Sınav',
              'date': Timestamp.fromDate(date),
              'instruction': null,
              'hasInstruction': false,
              'attachments': [],
              'grades': grades,
              'termId': termId,
              'schoolTypeId': c.typeId,
              'createdAt': Timestamp.fromDate(date),
              'updatedAt': Timestamp.fromDate(date),
              ..._demoFlag(inst),
            },
          );
          count('Yazılı Sınav');
        }
      }
    }
    await w.flush();

    // ── 7. Yoklama ─────────────────────────────────────────────────
    report('Yoklama kayıtları üretiliyor...', 0.74);
    final schoolDays = <DateTime>[];
    var cursor = today.subtract(const Duration(days: 1));
    while (schoolDays.length < 15 && cursor.isAfter(termStart)) {
      if (cursor.weekday != DateTime.saturday &&
          cursor.weekday != DateTime.sunday) {
        schoolDays.add(cursor);
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    for (final c in allClasses) {
      final students = studentsByClass[c.id] ?? const [];
      for (int di = 0; di < schoolDays.length; di++) {
        final day = schoolDays[di];
        final dateStr = _ymd(day);
        for (int hour = 1; hour <= 2; hour++) {
          final l = c.lessons[(di + hour) % c.lessons.length];
          final docId = '${_p}period_${c.id}_${l.id}_${dateStr}_$hour';
          final statuses = <String, String>{};
          for (final s in students) {
            final r = rng.nextDouble();
            // Zayıf öğrencilerde devamsızlık biraz daha yüksek
            final absentLimit = s.ability < 0.4 ? 0.10 : 0.03;
            if (r < absentLimit) {
              statuses[s.id] = 'absent';
            } else if (r < absentLimit + 0.03) {
              statuses[s.id] = 'late';
            } else if (r < absentLimit + 0.05) {
              statuses[s.id] = 'excused';
            } else {
              statuses[s.id] = 'present';
            }
          }
          await w.set(_db.collection('lessonAttendance').doc(docId), {
            'id': docId,
            'institutionId': inst,
            'schoolTypeId': c.typeId,
            'periodId': '${_p}wp_${c.typeId}',
            'classId': c.id,
            'className': c.name,
            'lessonId': l.id,
            'lessonName': l.name,
            'teacherId': l.teacherId,
            'date': dateStr,
            'lessonHour': hour,
            'allowedLessonHours': [hour],
            'studentStatuses': statuses,
            'method': 'demo',
            'updatedAt': FieldValue.serverTimestamp(),
            ..._demoFlag(inst),
          });
          count('Yoklama');
        }
      }
    }
    await w.flush();

    // ── 8. Deneme sınavları ────────────────────────────────────────
    report('Deneme sınavları ve sonuçları üretiliyor...', 0.80);
    await _seedTrialExams(
      inst: inst,
      termId: termId,
      termStart: termStart,
      today: today,
      types: types,
      studentsByTypeLevel: studentsByTypeLevel,
      w: w,
      rng: rng,
      count: count,
    );
    await w.flush();

    // ── 9. Etütler ─────────────────────────────────────────────────
    report('Etüt talepleri üretiliyor...', 0.90);
    int etutIdx = 0;
    for (final c in allClasses) {
      if (etutIdx % 2 == 1) {
        etutIdx++;
        continue;
      }
      final students = studentsByClass[c.id] ?? const [];
      if (students.isEmpty) continue;
      for (int k = 0; k < 2; k++) {
        final l = c.lessons[(k + 1) % math.min(4, c.lessons.length)];
        final dayOffset = k == 0
            ? -(7 + rng.nextInt(14))
            : (2 + rng.nextInt(10));
        var date = today.add(Duration(days: dayOffset));
        if (date.weekday == DateTime.saturday)
          date = date.add(const Duration(days: 2));
        if (date.weekday == DateTime.sunday)
          date = date.add(const Duration(days: 1));
        final start = DateTime(date.year, date.month, date.day, 15 + k, 30);
        final end = start.add(const Duration(minutes: 40));
        final picked = <DemoStudentInfo>[
          students[(k * 3 + 1) % students.length],
          students[(k * 3 + 5) % students.length],
        ];
        final uniq = {for (final s in picked) s.id: s}.values.toList();
        final id = '${_p}et_${c.id}_$k';
        await w.set(_db.collection('etut_requests').doc(id), {
          'id': id,
          'institutionId': inst,
          'studentId': uniq.first.id,
          'studentIds': uniq.map((s) => s.id).toList(),
          'recipientNames': {
            for (final s in uniq) s.id: '${s.fullName} (${c.name})',
          },
          'teacherId': l.teacherId,
          'teacherName': l.teacherName,
          'dersId': l.id,
          'dersAdi': l.name,
          'lessonName': l.name,
          'date': Timestamp.fromDate(date),
          'startTime': Timestamp.fromDate(start),
          'endTime': Timestamp.fromDate(end),
          'className': c.name,
          'classId': c.id,
          'status': 'active',
          'type': 'Etut',
          'isRecurring': false,
          'isGroup': uniq.length > 1,
          'groupStudentCount': uniq.length,
          'termId': termId,
          'schoolTypeId': c.typeId,
          'createdAt': FieldValue.serverTimestamp(),
          ..._demoFlag(inst),
        });
        count('Etüt');
      }
      etutIdx++;
    }
    await w.flush();

    // ── 10. Duyurular ──────────────────────────────────────────────
    if (schoolDocId.isNotEmpty) {
      report('Duyurular ve yemek listesi üretiliyor...', 0.95);
      final announcements = <List<String>>[
        [
          'Veli Toplantısı Hakkında',
          'Dönem ilk veli toplantımız bu cuma saat 18:30\'da okulumuzda yapılacaktır. Katılımınız önemlidir.',
        ],
        [
          'Deneme Sınavı Takvimi Yayınlandı',
          'Bu dönemki deneme sınavlarının tarihleri ve kapsamları portalda yayınlanmıştır. Öğrencilerimize başarılar dileriz.',
        ],
        [
          'Kütüphane Haftası Etkinlikleri',
          'Kütüphane haftası kapsamında kitap tanıtımı, yazar söyleşisi ve okuma yarışması düzenlenecektir.',
        ],
        [
          'Karne ve Dönem Değerlendirme Duyurusu',
          'Birinci dönem değerlendirme toplantıları aralık ayının ilk haftasında yapılacaktır.',
        ],
        [
          'Okul Gezisi Bilgilendirmesi',
          '7. ve 8. sınıflarımız için bilim merkezi gezisi planlanmıştır. İzin formlarını sınıf öğretmenlerine iletiniz.',
        ],
      ];
      for (int i = 0; i < announcements.length; i++) {
        final ts = now.subtract(Duration(days: 2 + i * 3));
        await w.set(
          _db
              .collection('schools')
              .doc(schoolDocId)
              .collection('announcements')
              .doc('${_p}an_$i'),
          {
            'title': announcements[i][0],
            'content': announcements[i][1],
            'summary': announcements[i][1],
            'status': 'published',
            'approvalStatus': 'approved',
            'schoolTypeId': '',
            'recipients': [],
            'publishDate': Timestamp.fromDate(ts),
            'createdAt': Timestamp.fromDate(ts),
            'createdBy': 'demo@edukn',
            'institutionId': inst,
            ..._demoFlag(inst),
          },
        );
        count('Duyuru');
      }

      // Yemek listesi (bu hafta ve gelecek hafta)
      final mealPeriods = <String, List<String>>{
        '${_p}meal_breakfast': ['Kahvaltı', '08:00', '08:30'],
        '${_p}meal_lunch': ['Öğle Yemeği', '12:15', '13:00'],
        '${_p}meal_snack': ['İkindi Ara Öğünü', '15:30', '15:45'],
      };
      for (final e in mealPeriods.entries) {
        await w.set(
          _db
              .collection('schools')
              .doc(schoolDocId)
              .collection('mealPeriods')
              .doc(e.key),
          {
            'name': e.value[0],
            'startTime': e.value[1],
            'endTime': e.value[2],
            'isActive': true,
            'schoolTypeIds': [],
            'institutionId': inst,
            ..._demoFlag(inst),
          },
        );
        count('Öğün');
      }
      final menus = <String, List<List<Object>>>{
        '${_p}meal_breakfast': [
          ['Haşlanmış Yumurta, Peynir, Zeytin, Domates', 280],
          ['Tost, Süt, Meyve', 320],
          ['Omlet, Beyaz Peynir, Salatalık', 300],
          ['Bal-Tereyağı, Kaşar, Çay/Süt', 310],
          ['Simit, Peynir, Meyve Suyu', 340],
        ],
        '${_p}meal_lunch': [
          ['Mercimek Çorbası, Tavuk Sote, Pirinç Pilavı, Ayran', 720],
          ['Domates Çorbası, Köfte, Bulgur Pilavı, Mevsim Salata', 760],
          ['Ezogelin Çorbası, Fırın Tavuk, Makarna, Yoğurt', 740],
          ['Yayla Çorbası, Kuru Fasulye, Pilav, Turşu', 700],
          ['Tarhana Çorbası, Balık, Patates Püresi, Salata', 690],
        ],
        '${_p}meal_snack': [
          ['Meyve Tabağı', 90],
          ['Kek ve Süt', 220],
          ['Kurabiye ve Ayran', 200],
          ['Meyveli Yoğurt', 160],
          ['Sandviç ve Meyve Suyu', 250],
        ],
      };
      final monday = today.subtract(Duration(days: today.weekday - 1));
      for (int weekIdx = 0; weekIdx < 2; weekIdx++) {
        for (int d = 0; d < 5; d++) {
          final day = monday.add(Duration(days: weekIdx * 7 + d));
          for (final entry in menus.entries) {
            final item = entry.value[(d + weekIdx * 2) % entry.value.length];
            await w.set(
              _db
                  .collection('schools')
                  .doc(schoolDocId)
                  .collection('mealPeriods')
                  .doc(entry.key)
                  .collection('menus')
                  .doc('${_p}menu_${entry.key}_${_ymd(day)}'),
              {
                'date': Timestamp.fromDate(day),
                'foodName': item[0] as String,
                'calories': item[1] as int,
                ..._demoFlag(inst),
              },
            );
            count('Menü');
          }
        }
      }
    } else {
      notes.add(
        'Okul dokümanı bulunamadığı için duyuru ve yemek listesi atlandı.',
      );
    }

    await w.flush();
    // Ek modül üreticileri (ders programı, rehberlik, muhasebe, destek hizmetleri vb.)
    registerAllDemoSeeders();
    final ctx = DemoSeedContext(
      db: _db,
      inst: inst,
      prefix: _p,
      termId: termId,
      termStart: termStart,
      today: today,
      rng: rng,
      w: w,
      schoolDocId: schoolDocId,
      types: types,
      classes: allClasses,
      studentsByClass: studentsByClass,
      teachers: teacherInfos,
      counts: counts,
    );
    final totalSeeders = DemoSeedRegistry.seeders.length;
    int doneSeeders = 0;
    await DemoSeedRegistry.seedAll(
      ctx,
      onStep: (name) {
        doneSeeders++;
        report(
          '$name üretiliyor...',
          0.96 + 0.035 * (doneSeeders / (totalSeeders == 0 ? 1 : totalSeeders)),
        );
      },
    );
    await w.flush();
    report('Tamamlandı!', 1.0);
    notes.add(
      'Öğrenci giriş: demo<no> / demo123 • Veli: veli<no> / demo123 (Auth hesabı oluşturulmadı).',
    );
    return DemoSeedResult(counts: counts, totalDocs: w.total, notes: notes);
  }

  // ═════════════════════════ DENEME SINAVLARI ═════════════════════════
  static Future<void> _seedTrialExams({
    required String inst,
    required String termId,
    required DateTime termStart,
    required DateTime today,
    required List<DemoTypeDef> types,
    required Map<String, List<DemoStudentInfo>> studentsByTypeLevel,
    required DemoBatchWriter w,
    required math.Random rng,
    required void Function(String, [int]) count,
  }) async {
    // Sınav türleri (kurum başına bir kez)
    final Map<String, _ExamTypeDef> examTypes = {};
    Future<_ExamTypeDef> ensureType(
      String key,
      String name,
      String gradeLevel,
      List<_SubjectDef> subjects,
      double ratio,
      double base,
      double max,
    ) async {
      if (examTypes.containsKey(key)) return examTypes[key]!;
      final def = _ExamTypeDef(
        id: '${_p}et_$key',
        name: name,
        subjects: subjects,
        ratio: ratio,
        base: base,
        max: max,
      );
      await w.set(_db.collection('exam_types').doc(def.id), {
        'id': def.id,
        'name': name,
        'gradeLevel': gradeLevel,
        'institutionId': inst,
        'baseScore': base,
        'maxScore': max,
        'wrongCorrectRatio': ratio,
        'optionCount': key.startsWith('tyt') ? 5 : 4,
        'subjects': subjects
            .map(
              (s) => {
                'branchName': s.name,
                'questionCount': s.questions,
                'coefficient': s.coefficient,
              },
            )
            .toList(),
        'isActive': true,
        ..._demoFlag(inst),
      });
      count('Sınav Türü');
      examTypes[key] = def;
      return def;
    }

    for (final type in types) {
      final isLise = type.kind == 'Lise';
      final isOrta = type.kind == 'Ortaokul';
      if (!isLise && !isOrta) continue;
      final typeKey = _slug(type.id).length > 14
          ? _slug(type.id).substring(0, 14)
          : _slug(type.id);

      for (final level in type.levels) {
        final students = studentsByTypeLevel['${type.id}|$level'] ?? const [];
        if (students.isEmpty) continue;

        late final _ExamTypeDef et;
        String examPrefix;
        if (isLise) {
          et = await ensureType(
            'tyt',
            'TYT Deneme Sınavı',
            '$level. Sınıf',
            _tytSubjects,
            4.0,
            100,
            500,
          );
          examPrefix = '$level. Sınıf TYT Deneme';
        } else if (level == 8) {
          et = await ensureType(
            'lgs',
            'LGS Deneme Sınavı',
            '8. Sınıf',
            _lgsSubjects,
            3.0,
            194.76,
            500,
          );
          examPrefix = '8. Sınıf LGS Deneme';
        } else {
          et = await ensureType(
            'genelorta',
            'Ortaokul Genel Deneme',
            '$level. Sınıf',
            _genelOrtaokulSubjects,
            3.0,
            0,
            500,
          );
          examPrefix = '$level. Sınıf Genel Deneme';
        }

        // 3 genel deneme (haftalar arası) ...
        final dayOffsets = [49, 28, 8];
        for (int k = 0; k < 3; k++) {
          var date = today.subtract(Duration(days: dayOffsets[k]));
          if (date.isBefore(termStart.add(const Duration(days: 4)))) {
            date = termStart.add(Duration(days: 6 + k * 10));
          }
          await _writeTrialExam(
            inst: inst,
            termId: termId,
            idSuffix: '${typeKey}_${level}_g$k',
            name: '$examPrefix - ${k + 1}',
            classLevel: '$level. Sınıf',
            et: et,
            subjects: et.subjects,
            date: date,
            students: students,
            examIndex: k,
            w: w,
            rng: rng,
          );
          count('Deneme Sınavı');
        }

        // ... ve 8. sınıf için farklı soru sayılı TARAMA sınavları (20 soru)
        if (isOrta && level == 8) {
          final fenTarama = await ensureType(
            'tarama_fen',
            'Fen Bilimleri Tarama Sınavı',
            '8. Sınıf',
            const [_SubjectDef('Fen Bilimleri', 20, 4.123)],
            3.0,
            0,
            100,
          );
          final matTarama = await ensureType(
            'tarama_mat',
            'Matematik Tarama Sınavı',
            '8. Sınıf',
            const [_SubjectDef('Matematik', 20, 4.254)],
            3.0,
            0,
            100,
          );
          await _writeTrialExam(
            inst: inst,
            termId: termId,
            idSuffix: '${typeKey}_${level}_tf',
            name: '8. Sınıf Fen Bilimleri Tarama Sınavı',
            classLevel: '8. Sınıf',
            et: fenTarama,
            subjects: fenTarama.subjects,
            date: today.subtract(const Duration(days: 20)),
            students: students,
            examIndex: 1,
            w: w,
            rng: rng,
          );
          await _writeTrialExam(
            inst: inst,
            termId: termId,
            idSuffix: '${typeKey}_${level}_tm',
            name: '8. Sınıf Matematik Tarama Sınavı',
            classLevel: '8. Sınıf',
            et: matTarama,
            subjects: matTarama.subjects,
            date: today.subtract(const Duration(days: 14)),
            students: students,
            examIndex: 2,
            w: w,
            rng: rng,
          );
          count('Deneme Sınavı', 2);
        }
      }
    }
  }

  static Future<void> _writeTrialExam({
    required String inst,
    required String termId,
    required String idSuffix,
    required String name,
    required String classLevel,
    required _ExamTypeDef et,
    required List<_SubjectDef> subjects,
    required DateTime date,
    required List<DemoStudentInfo> students,
    required int examIndex,
    required DemoBatchWriter w,
    required math.Random rng,
  }) async {
    const letters = ['A', 'B', 'C', 'D'];
    final answerKey = <String, String>{};
    final outcomes = <String, List<String>>{};
    final qDifficulty = <String, List<double>>{};
    final outcomeNames = <String, List<String>>{};
    for (final s in subjects) {
      final sb = StringBuffer();
      final diff = <double>[];
      for (int q = 0; q < s.questions; q++) {
        sb.write(letters[rng.nextInt(4)]);
        diff.add((rng.nextDouble() - 0.55) * 0.5);
      }
      answerKey[s.name] = sb.toString();
      qDifficulty[s.name] = diff;
      final outs = _outcomesFor(s.name);
      outcomeNames[s.name] = outs;
      outcomes[s.name] = List.generate(
        s.questions,
        (q) => outs[q % outs.length],
      );
    }

    final rows = <Map<String, dynamic>>[];
    for (final st in students) {
      // %6 devamsız öğrenci
      if (rng.nextDouble() < 0.06) continue;
      final subjectStats = <String, Map<String, dynamic>>{};
      final answers = <String, String>{};
      double weighted = 0;
      double totalNet = 0;
      int sIdx = 0;
      for (final s in subjects) {
        final off = st.subjectOffsets[sIdx % 8] ?? 0.0;
        // Zamanla hafif gelişim + sınav başı sapma
        final level =
            st.ability +
            off +
            examIndex * 0.025 +
            (rng.nextDouble() - 0.5) * 0.08;
        int c = 0, wr = 0, e = 0;
        final key = answerKey[s.name]!;
        final diff = qDifficulty[s.name]!;
        final ans = StringBuffer();
        for (int q = 0; q < s.questions; q++) {
          final p = (level + diff[q]).clamp(0.03, 0.98);
          final r = rng.nextDouble();
          if (r < p) {
            c++;
            ans.write(key[q]);
          } else if (r < p + (1 - p) * 0.30) {
            e++;
            ans.write(' ');
          } else {
            wr++;
            final others = letters.where((l) => l != key[q]).toList();
            ans.write(others[rng.nextInt(others.length)]);
          }
        }
        final net = c - wr / et.ratio;
        subjectStats[s.name] = {
          'correct': c,
          'wrong': wr,
          'empty': e,
          'net': double.parse(net.toStringAsFixed(2)),
        };
        answers[s.name] = ans.toString();
        weighted += net * s.coefficient;
        totalNet += net;
        sIdx++;
      }
      final totalQ = subjects.fold<int>(0, (a, s) => a + s.questions);
      double score;
      if (et.base > 0) {
        score = et.base + weighted;
      } else {
        score = (totalNet / totalQ) * et.max;
      }
      score = score.clamp(0.0, et.max);

      rows.add({
        'tcNo': st.tc,
        'studentNo': st.no,
        'name': st.fullName,
        'classLevel': '${st.level}',
        'branch': st.className,
        'booklet': 'A',
        'score': double.parse(score.toStringAsFixed(3)),
        'rankGeneral': 0,
        'rankInstitution': 0,
        'rankBranch': 0,
        'subjects': subjectStats,
        'answers': answers,
        'correctAnswers': answerKey,
        'isMatched': true,
        'systemStudentId': st.id,
        'participatedSessions': [1],
      });
    }

    rows.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final branchCounter = <String, int>{};
    for (int i = 0; i < rows.length; i++) {
      rows[i]['rankGeneral'] = i + 1;
      rows[i]['rankInstitution'] = i + 1;
      final b = rows[i]['branch'] as String;
      branchCounter[b] = (branchCounter[b] ?? 0) + 1;
      rows[i]['rankBranch'] = branchCounter[b];
    }

    final id = '${_p}te_$idSuffix';
    await w.set(_db.collection('trial_exams').doc(id), {
      'id': id,
      'institutionId': inst,
      'name': name,
      'classLevel': classLevel,
      'examTypeId': et.id,
      'examTypeName': et.name,
      'applicationType': 0,
      'bookletCount': 1,
      'sessionCount': 1,
      'answerKeys': {'A': answerKey},
      'outcomes': {'A': outcomes},
      'sessions': [
        {
          'sessionNumber': 1,
          'selectedSubjects': subjects.map((s) => s.name).toList(),
          'opticalFormId': null,
          'opticalFormName': null,
          'fileName': null,
          'fileUrl': null,
          'uploadedAt': Timestamp.fromDate(date),
          'lineEdits': [],
        },
      ],
      'selectedBranches': [],
      'date': Timestamp.fromDate(date),
      'isActive': true,
      'isPublished': true,
      'isLaunched': true,
      'resultsJson': jsonEncode(rows),
      'sharingSettings': {},
      'bookletMapping': {},
      'termId': termId,
      'durationMinutes': subjects.length == 1 ? 40 : 135,
      'totalQuestions': subjects.fold<int>(0, (a, s) => a + s.questions),
      ..._demoFlag(inst),
    });
  }

  // ═══════════════════════════════ TEMİZLE ═══════════════════════════════
  /// Yalnızca `isDemo == true` dokümanlarını siler. Silinen doküman sayısını döner.
  static Future<int> clear({
    required String institutionId,
    void Function(String message, double progress)? onProgress,
  }) async {
    final inst = institutionId.trim();
    if (inst.isEmpty) return 0;
    _p = _prefixFor(inst);
    int deleted = 0;
    var batch = _db.batch();
    int pending = 0;

    Future<void> queueDelete(DocumentReference ref) async {
      batch.delete(ref);
      pending++;
      deleted++;
      if (pending >= 400) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    // Önce iç içe (alt koleksiyon) temizleyiciler: üst dokümanlar silinmeden çalışmalıdır.
    registerAllDemoSeeders();
    for (final cleaner in DemoSeedRegistry.extraCleaners) {
      try {
        final sid = await _resolveSchoolDocId(inst);
        deleted += await cleaner(_db, inst, _p, sid);
      } catch (e) {
        debugPrint('[DemoSeeder] ek temizleyici hata: $e');
      }
    }

    int i = 0;
    for (final col in _topCollections) {
      onProgress?.call('$col temizleniyor...', i / _topCollections.length);
      i++;
      try {
        final snap = await _db
            .collection(col)
            .where('institutionId', isEqualTo: inst)
            .where('isDemo', isEqualTo: true)
            .get();
        for (final d in snap.docs) {
          await queueDelete(d.reference);
        }
      } catch (e) {
        debugPrint('[DemoSeeder] $col temizlenemedi: $e');
      }
    }

    // Okul dokümanı altındaki duyuru / yemek verileri
    try {
      final schoolDocId = await _resolveSchoolDocId(inst);
      if (schoolDocId.isNotEmpty) {
        final schoolRef = _db.collection('schools').doc(schoolDocId);
        final ann = await schoolRef
            .collection('announcements')
            .where('isDemo', isEqualTo: true)
            .get();
        for (final d in ann.docs) {
          await queueDelete(d.reference);
        }
        for (final pid in _demoMealPeriodIds) {
          final periodRef = schoolRef.collection('mealPeriods').doc(pid);
          final menus = await periodRef
              .collection('menus')
              .where('isDemo', isEqualTo: true)
              .get();
          for (final d in menus.docs) {
            await queueDelete(d.reference);
          }
          await queueDelete(periodRef);
        }
      }
    } catch (e) {
      debugPrint('[DemoSeeder] okul alt koleksiyonları temizlenemedi: $e');
    }

    registerAllDemoSeeders();
    // Ek modüllerin koleksiyonları
    for (final col in DemoSeedRegistry.topCollections) {
      try {
        final snap = await _db
            .collection(col)
            .where('institutionId', isEqualTo: inst)
            .where('isDemo', isEqualTo: true)
            .get();
        for (final d in snap.docs) {
          await queueDelete(d.reference);
        }
      } catch (e) {
        debugPrint('[DemoSeeder] $col temizlenemedi: $e');
      }
    }
    try {
      final sid = await _resolveSchoolDocId(inst);
      if (sid.isNotEmpty) {
        for (final sub in DemoSeedRegistry.schoolSubcollections) {
          final snap = await _db
              .collection('schools')
              .doc(sid)
              .collection(sub)
              .where('isDemo', isEqualTo: true)
              .get();
          for (final d in snap.docs) {
            await queueDelete(d.reference);
          }
        }
      }
    } catch (e) {
      debugPrint('[DemoSeeder] okul alt koleksiyonları temizlenemedi: $e');
    }
    if (pending > 0) {
      await batch.commit();
      batch = _db.batch();
      pending = 0;
    }
    if (pending > 0) await batch.commit();
    onProgress?.call('Temizlik tamamlandı.', 1.0);
    return deleted;
  }

  // ═══════════════════════════════ YARDIMCILAR ═══════════════════════════════
  static Map<String, dynamic> _demoFlag(String inst) => {
    'isDemo': true,
    'demoTag': demoTag,
  };

  static Future<String> _resolveSchoolDocId(String inst) async {
    try {
      final variants = <String>{
        inst,
        inst.toUpperCase(),
        inst.toLowerCase(),
      }.toList();
      final snap = await _db
          .collection('schools')
          .where('institutionId', whereIn: variants)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (e) {
      debugPrint('[DemoSeeder] okul dokümanı çözümlenemedi: $e');
    }
    return '';
  }

  static List<_LessonDef> _lessonDefsFor(String kind) {
    switch (kind) {
      case 'Lise':
        return _liseLessons;
      case 'Ortaokul':
        return _ortaokulLessons;
      case 'Anaokulu':
        return _anaokuluLessons;
      default:
        return _ilkokulLessons;
    }
  }

  static List<int> _levelsFor(String kind, dynamic activeGrades) {
    final levels = <int>[];
    if (activeGrades is List) {
      for (final g in activeGrades) {
        final m = RegExp(r'\d+').firstMatch(g.toString());
        if (m != null) {
          final v = int.tryParse(m.group(0)!);
          if (v != null && v >= 1 && v <= 12) levels.add(v);
        }
      }
    }
    if (levels.isNotEmpty) {
      levels.sort();
      return levels.toSet().toList()..sort();
    }
    switch (kind) {
      case 'Anaokulu':
        return [3, 4, 5];
      case 'İlkokul':
        return [1, 2, 3, 4];
      case 'Ortaokul':
        return [5, 6, 7, 8];
      case 'Lise':
        return [9, 10, 11, 12];
      default:
        return [];
    }
  }

  static String _hwTitle(String lesson, int idx) {
    const titles = [
      'Konu Tekrarı Soruları',
      'Alıştırma Çalışma Kağıdı',
      'Haftalık Test',
    ];
    return '$lesson - ${titles[idx % titles.length]}';
  }

  static List<String> _outcomesFor(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('matematik')) {
      return const [
        'Çarpanlar ve Katlar',
        'Üslü İfadeler',
        'Kareköklü İfadeler',
        'Veri Analizi',
        'Olasılık',
        'Cebirsel İfadeler ve Özdeşlikler',
        'Doğrusal Denklemler',
        'Eşitsizlikler',
      ];
    }
    if (s.contains('fen') ||
        s.contains('fizik') ||
        s.contains('kimya') ||
        s.contains('biyoloji')) {
      return const [
        'Mevsimler ve İklim',
        'DNA ve Genetik Kod',
        'Basınç',
        'Madde ve Endüstri',
        'Basit Makineler',
        'Enerji Dönüşümleri',
        'Elektrik Yükleri',
        'Kimyasal Tepkimeler',
      ];
    }
    if (s.contains('türkçe') || s.contains('edebiyat')) {
      return const [
        'Sözcükte Anlam',
        'Cümlede Anlam',
        'Paragrafta Anlam',
        'Fiilimsiler',
        'Cümle Türleri',
        'Yazım ve Noktalama',
        'Anlatım Bozuklukları',
        'Metin Türleri',
      ];
    }
    if (s.contains('inkılap') ||
        s.contains('inkılap') ||
        s.contains('tarih') ||
        s.contains('sosyal')) {
      return const [
        'Bir Kahraman Doğuyor',
        'Milli Uyanış',
        'Milli Bir Destan',
        'Atatürkçülük ve Çağdaşlaşan Türkiye',
        'Demokratikleşme Çabaları',
        'Atatürk Dönemi Dış Politika',
      ];
    }
    if (s.contains('din')) {
      return const [
        'Kader İnancı',
        'Zekât ve Sadaka',
        'Din ve Hayat',
        'Hz. Muhammed\'in Örnekliği',
        'Kur\'an-ı Kerim ve Yorumu',
      ];
    }
    if (s.contains('dil') || s.contains('ingilizce')) {
      return const [
        'Friendship',
        'Teen Life',
        'In the Kitchen',
        'On the Phone',
        'The Internet',
        'Adventures',
      ];
    }
    return const ['Kazanım 1', 'Kazanım 2', 'Kazanım 3', 'Kazanım 4'];
  }

  static String _d2(int n) => n.toString().padLeft(2, '0');
  static String _ymd(DateTime d) => '${d.year}-${_d2(d.month)}-${_d2(d.day)}';

  static String _slug(String input) {
    const map = {
      'ç': 'c',
      'Ç': 'c',
      'ğ': 'g',
      'Ğ': 'g',
      'ı': 'i',
      'İ': 'i',
      'I': 'i',
      'ö': 'o',
      'Ö': 'o',
      'ş': 's',
      'Ş': 's',
      'ü': 'u',
      'Ü': 'u',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

// ═══════════════════════════ İç veri sınıfları ═══════════════════════════

class _LessonDef {
  final String name;
  final String shortName;
  final int weeklyHours;
  final String branch;
  const _LessonDef(this.name, this.shortName, this.weeklyHours, this.branch);
}

class _SubjectDef {
  final String name;
  final int questions;
  final double coefficient;
  const _SubjectDef(this.name, this.questions, this.coefficient);
}

class _ExamTypeDef {
  final String id;
  final String name;
  final List<_SubjectDef> subjects;
  final double ratio;
  final double base;
  final double max;
  const _ExamTypeDef({
    required this.id,
    required this.name,
    required this.subjects,
    required this.ratio,
    required this.base,
    required this.max,
  });
}
