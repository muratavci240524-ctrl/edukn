import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:archive/archive.dart';

class PortfolioReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    return DateTime.now();
  }

  Future<Map<String, dynamic>> fetchFullPortfolioData({
    required String studentId,
    required String institutionId,
    required String termId,
  }) async {
    final studentDoc = await _firestore.collection('students').doc(studentId).get();
    final studentData = studentDoc.data() ?? {};
    
    // Fetch all sub-modules in parallel for efficiency
    final results = await Future.wait([
      _fetchTrialExams(studentId, institutionId, termId),
      _fetchWrittenExams(studentId, institutionId, termId),
      _fetchHomeworks(studentId, institutionId, termId),
      _fetchAttendance(studentId, institutionId, termId),
      _fetchEtuts(studentId, institutionId, termId),
      _fetchBooks(studentId, institutionId, termId),
      _fetchInterviews(studentId, institutionId, termId),
      _fetchDevelopmentReports(studentId, institutionId, termId),
      _fetchStudyPrograms(studentId, institutionId, termId),
      _fetchTests(studentId, institutionId, termId),
      _fetchActivities(studentId, institutionId, termId),
    ]);

    final trialExams = results[0] as List;
    final writtenExams = results[1] as List;
    final homeworks = results[2] as List;
    final attendance = results[3] as List;

    // --- Summary Calculations ---
    double avgPoint = 0;
    double avgNet = 0;
    Map<String, double> subjectAvgNets = {};
    Map<String, int> subjectQuestionCounts = {};
    Map<String, Map<String, Map<String, dynamic>>> globalTopicStats = {};

    if (trialExams.isNotEmpty) {
      avgPoint = trialExams.map((e) => (e['score'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a + b) / trialExams.length;
      avgNet = trialExams.map((e) => (e['net'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a + b) / trialExams.length;

      // Subject & Topic aggregation
      int examCount = trialExams.length;
      int processCount = 0;
      for (var exam in trialExams) {
        processCount++;
        if (processCount % 5 == 0) await Future.delayed(Duration.zero); 

        final subjects = exam['subjects'] as Map? ?? {};
        subjects.forEach((subj, data) {
          if (data is Map) {
            final sNet = _toNum(data['net'] ?? data['netler'] ?? 0.0).toDouble();
            int sQ = _toNum(data['q'] ?? data['soru'] ?? data['soruSayisi'] ?? data['total'] ?? data['count'] ?? 0).toInt();
            
            // LGS Defaults if zero
            if (sQ == 0) {
                final code = _mapSubjectToCode(subj.toString());
                if (['TRK', 'MAT', 'FEN'].contains(code)) sQ = 20;
                else if (['SOS', 'İNG', 'DİN'].contains(code)) sQ = 10;
                else sQ = 10;
            }

            subjectAvgNets[subj.toString()] = (subjectAvgNets[subj.toString()] ?? 0.0) + (sNet / examCount);
            
            if (sQ > (subjectQuestionCounts[subj.toString()] ?? 0)) {
              subjectQuestionCounts[subj.toString()] = sQ;
            }
          }
        });

        final tAnalysis = exam['topicAnalysis'] as Map? ?? {};
        tAnalysis.forEach((subj, topics) {
          final subjStr = subj.toString();
          if (!globalTopicStats.containsKey(subjStr)) globalTopicStats[subjStr] = {};
          
          if (topics is List) {
            for (var t in topics) {
              if (t is Map) {
                final tName = t['name']?.toString() ?? 'Adsız Konu';
                if (!globalTopicStats[subjStr]!.containsKey(tName)) {
                  globalTopicStats[subjStr]![tName] = {'ss': 0, 'd': 0, 'y': 0, 'b': 0, 'net': 0.0};
                }
                final stats = globalTopicStats[subjStr]![tName]!;
                stats['ss'] += 1;
                stats['d'] += (t['d'] ?? t['dogru'] ?? 0) as int;
                stats['y'] += (t['y'] ?? t['yanlis'] ?? 0) as int;
                stats['b'] += (t['b'] ?? t['bos'] ?? 0) as int;
                stats['net'] += (t['net'] ?? t['netler'] ?? 0.0) as num;
              }
            }
          }
        });
      }
    }

    int totalHw = homeworks.length;
    int completedHw = 0;
    for (var hMap in homeworks) {
        final h = hMap as Map<String, dynamic>;
        final statuses = h['studentStatuses'] as Map? ?? {};
        final status = statuses[studentId];
        // 1 = completed in HomeworkStatus enum
        if (status == 1 || status == "1" || h['status'] == 'Tamamlandı' || h['status'] == 'Done') {
            completedHw++;
        }
    }
    int missingHw = totalHw - completedHw;

    double totalAbsence = 0;
    List<Map<String, dynamic>> attendanceDetails = [];
    for (var attMap in attendance) {
      final Map<String, dynamic> data = attMap as Map<String, dynamic>;
      final statuses = data['studentStatuses'] as Map? ?? {};
      final status = (statuses[studentId] ?? '').toString();
      
      if (status != 'present' && status != '') {
        if (status == 'absent') totalAbsence += 1.0;
        else totalAbsence += 0.5;

        attendanceDetails.add({
          'date': _parseDate(data['date']),
          'status': status,
          'lessonName': data['lessonName'] ?? '-',
          'period': data['period'] ?? '-',
        });
      }
    }

    // Add student photo if exists
    Uint8List? studentPhoto;
    if (studentData['photoUrl'] != null && studentData['photoUrl'].toString().isNotEmpty) {
      try {
        studentPhoto = await fetchFileBytes(studentData['photoUrl']);
      } catch (e) {
        print("Error fetching student photo: $e");
      }
    }

    return {
      ...studentData,
      'studentId': studentId,
      'studentPhoto': studentPhoto,
      'summary': {
        'avgPoint': avgPoint,
        'avgNet': avgNet,
        'totalHw': totalHw,
        'completedHw': completedHw,
        'missingHw': missingHw,
        'totalAbsence': totalAbsence,
        'subjectAvgNets': _normalizeSubjectMap(subjectAvgNets),
        'subjectQuestionCounts': _normalizeSubjectMapInt(subjectQuestionCounts),
        'globalTopicStats': globalTopicStats,
        'examCount': trialExams.length,
      },
      'trialExams': trialExams,
      'writtenExams': writtenExams,
      'homeworks': homeworks,
      'attendance': attendanceDetails,
      'etuts': results[4],
      'books': results[5],
      'interviews': results[6],
      'developmentReports': results[7],
      'studyPrograms': results[8],
      'tests': results[9],
      'activities': results[10],
    };
  }

  String _mapSubjectToCode(String subject) {
    // Normalizing characters to avoid i/İ issues
    final s = subject.toLowerCase().trim()
        .replaceAll('i̇', 'i').replaceAll('ı', 'i')
        .replaceAll('ö', 'o').replaceAll('ü', 'u')
        .replaceAll('ş', 's').replaceAll('ç', 'c')
        .replaceAll('ğ', 'g');
        
    if (s.contains('turkce') || s.contains('trk') || s.contains('tur')) return 'TRK';
    if (s.contains('matematik') || s.contains('mat') || s.contains('mtm')) return 'MAT';
    if (s.contains('fen') || s.contains('bilim') || s.contains('fb')) return 'FEN';
    if (s.contains('sosyal') || s.contains('sos') || s.contains('ink') || s.contains('sb')) return 'SOS';
    if (s.contains('ing') || s.contains('eng')) return 'İNG';
    if (s.contains('din') || s.contains('dkab') || s.contains('ahlak')) return 'DİN';
    return subject.toUpperCase();
  }

  Map<String, double> _normalizeSubjectMap(Map<String, double> map) {
    Map<String, double> normalized = {};
    map.forEach((key, value) {
      final code = _mapSubjectToCode(key);
      normalized[code] = (normalized[code] ?? 0.0) + value;
    });
    return normalized;
  }

  Map<String, int> _normalizeSubjectMapInt(Map<String, int> map) {
    Map<String, int> normalized = {};
    map.forEach((key, value) {
      final code = _mapSubjectToCode(key);
      normalized[code] = value; // Usually question counts are same for same subject code
    });
    return normalized;
  }

  Future<Uint8List?> fetchFileBytes(String url) async {
    try {
      final response = await _fetchBytesFromUrl(url);
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List> _fetchBytesFromUrl(String url) async {
     try {
       final ref = FirebaseStorage.instance.refFromURL(url);
       return (await ref.getData())!;
     } catch (e) {
       return Uint8List(0);
     }
  }

  Future<List<Map<String, dynamic>>> _fetchTrialExams(String id, String inst, String term) async {
    final studentDoc = await _firestore.collection('students').doc(id).get();
    final studentData = studentDoc.data() ?? {};
    
    // Identifiers for robust matching
    final String sId = id.toString();
    final String sNo = (studentData['schoolNumber'] ?? studentData['studentNumber'] ?? studentData['no'] ?? '').toString().trim();
    final String sName = (studentData['fullName'] ?? studentData['name'] ?? '').toString().toLowerCase().trim();

    final query = await _firestore
        .collection('trial_exams')
        .where('institutionId', isEqualTo: inst)
        .where('isActive', isEqualTo: true)
        .get();

    List<Map<String, dynamic>> studentResults = [];

    for (var doc in query.docs) {
      final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      final String? resultsJson = data['resultsJson'];
      if (resultsJson != null && resultsJson is String) {
        // Performance Optimization: Quick string search before JSON decode
        bool mightContain = resultsJson.contains(sId);
        if (!mightContain && sNo.isNotEmpty) mightContain = resultsJson.contains(sNo);
        if (!mightContain && sName.isNotEmpty) mightContain = resultsJson.toLowerCase().contains(sName);

        if (!mightContain) continue;

        try {
          final List<dynamic> allResults = jsonDecode(resultsJson);
          
          // ROBUST MATCHING LOGIC (Synced with UI)
          Map<String, dynamic>? match;

          // 1. Match by ID
          match = allResults.firstWhere((r) {
            final rId = (r['studentId'] ?? r['id'] ?? '').toString();
            return rId == sId;
          }, orElse: () => null);

          // 2. Match by School Number
          if (match == null && sNo.isNotEmpty) {
            match = allResults.firstWhere((r) {
              final rNo = (r['studentNumber'] ?? r['number'] ?? r['schoolNumber'] ?? r['no'] ?? '').toString().trim();
              return rNo == sNo;
            }, orElse: () => null);
          }

          // 3. Match by Name (Fuzzy)
          if (match == null && sName.isNotEmpty) {
            match = allResults.firstWhere((r) {
              final rName = (r['name'] ?? r['studentName'] ?? '').toString().toLowerCase().trim();
              return rName == sName || rName.contains(sName) || sName.contains(rName);
            }, orElse: () => null);
          }

          if (match != null) {
            final subjects = (match['subjects'] as Map? ?? match['dersler'] as Map? ?? match['results'] as Map? ?? {}).cast<String, dynamic>();
            
            // Robust Total Net & Total Point extraction
            double net = _toNum(match['net'] ?? match['totalNet'] ?? match['toplamNet'] ?? match['genelNet'] ?? 0.0).toDouble();
            final double score = _toNum(match['score'] ?? match['point'] ?? match['puan'] ?? match['toplamPuan'] ?? 0.0).toDouble();
            
            // If total net is 0, try to sum up subject nets
            if (net == 0 && subjects.isNotEmpty) {
              subjects.forEach((key, value) {
                if (value is Map) {
                  net += _toNum(value['net'] ?? value['netler'] ?? 0).toDouble();
                }
              });
            }

            int totalQ = 0;
            subjects.forEach((key, value) {
                if (value is Map) {
                  totalQ += _toNum(value['q'] ?? value['soru'] ?? value['soruSayisi'] ?? value['total'] ?? 0).toInt();
                }
            });
            
            // Fallback for LGS (90 questions) if totalQ still 0, to avoid 0% in charts
            if (totalQ == 0) {
              totalQ = 90;
            }

            // Extract Topic Analysis if exists in standard results
            final tAnalysis = (match['topicAnalysis'] as Map? ?? match['konuAnalizi'] as Map? ?? {}).cast<String, dynamic>();

            final double percentile = _toNum(match['percentile'] ?? match['yuzdelik'] ?? match['dilim'] ?? 0.0).toDouble();

            studentResults.add({
              'examName': data['name'] ?? 'Adsız Sınav',
              'date': _parseDate(data['date']),
              'score': score,
              'net': net,
              'percentile': percentile,
              'totalQuestions': totalQ,
              'success': totalQ > 0 ? (net / totalQ * 100).clamp(0, 100) : 0.0,
              'subjects': subjects,
              'topicAnalysis': tAnalysis,
            });
          }
        } catch (e) {
          print("Error parsing resultsJson for exam ${doc.id}: $e");
        }
      }
    }
    
    // Sort exams by date descending (sync with UI "Sınav Geçmişi")
    studentResults.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    return studentResults;
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return double.tryParse(v.toString()) ?? 0;
  }

  Future<List<Map<String, dynamic>>> _fetchWrittenExams(String id, String inst, String term) async {
    final query = await _firestore
        .collection('class_exams')
        .where('institutionId', isEqualTo: inst)
        .get();
    
    List<Map<String, dynamic>> results = [];
    for (var doc in query.docs) {
      final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      final scores = data['scores'] as Map? ?? data['grades'] as Map?;
      if (scores != null && scores.containsKey(id)) {
        results.add({
          'examName': data['name'] ?? 'Yazılı Sınav',
          'date': _parseDate(data['date']),
          'score': scores[id],
          'subject': data['subject'] ?? data['lessonName'] ?? '',
        });
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> _fetchHomeworks(String id, String inst, String term) async {
    final studentDoc = await _firestore.collection('students').doc(id).get();
    final studentData = studentDoc.data() ?? {};
    final classId = studentData['classId'];

    final List<Future<QuerySnapshot>> queries = [
      _firestore.collection('homeworks')
          .where('institutionId', isEqualTo: inst)
          .where('targetStudentIds', arrayContains: id)
          .get(),
    ];

    if (classId != null) {
      queries.add(_firestore.collection('homeworks')
          .where('institutionId', isEqualTo: inst)
          .where('classId', isEqualTo: classId)
          .get());
    }

    final snapshots = await Future.wait(queries);
    final allDocs = <String, DocumentSnapshot>{};
    for (var snap in snapshots) {
      for (var doc in snap.docs) {
        allDocs[doc.id] = doc;
      }
    }

    return allDocs.values.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAttendance(String id, String inst, String term) async {
    final studentDoc = await _firestore.collection('students').doc(id).get();
    final studentData = studentDoc.data() ?? {};
    final classId = studentData['classId'];

    if (classId == null) return [];

    final query = await _firestore
        .collection('lessonAttendance')
        .where('institutionId', isEqualTo: inst)
        .where('classId', isEqualTo: classId)
        .get();

    return query.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        final statuses = data['studentStatuses'] as Map? ?? {};
        return statuses.containsKey(id);
    }).map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchEtuts(String id, String inst, String term) async {
    final query = await _firestore
        .collection('etut_requests')
        .where('institutionId', isEqualTo: inst)
        .where('studentId', isEqualTo: id)
        .where('status', isEqualTo: 'Approved')
        .get();
    return query.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchBooks(String id, String inst, String term) async {
    final query = await _firestore
        .collection('book_assignments')
        .where('institutionId', isEqualTo: inst)
        .where('studentId', isEqualTo: id)
        .get();
    return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchInterviews(String id, String inst, String term) async {
    final query = await _firestore
        .collection('guidance_interviews')
        .where('institutionId', isEqualTo: inst)
        .where('participants', arrayContains: id)
        .get();
    return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchDevelopmentReports(String id, String inst, String term) async {
    final query = await _firestore
        .collection('development_reports')
        .where('institutionId', isEqualTo: inst)
        .where('studentId', isEqualTo: id)
        .get();
    return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchStudyPrograms(String id, String inst, String term) async {
    final query = await _firestore
        .collection('institutions')
        .doc(inst)
        .collection('study_programs')
        .where('studentId', isEqualTo: id)
        .get();
    return query.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return {
        'name': data['title'] ?? data['name'] ?? 'Çalışma Programı',
        'date': _parseDate(data['createdAt']),
        'progress': data['progress'] ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchTests(String id, String inst, String term) async {
    final query = await _firestore
        .collection('applied_tests')
        .where('studentId', isEqualTo: id)
        .get();
    return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchActivities(String id, String inst, String term) async {
    final query = await _firestore
        .collection('activity_reports')
        .where('studentId', isEqualTo: id)
        .get();
    return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Uint8List generateZip(List<Map<String, dynamic>> files) {
    final archive = Archive();
    for (var file in files) {
      final archiveFile = ArchiveFile(
        file['name'],
        (file['data'] as Uint8List).length,
        file['data'],
      );
      archive.addFile(archiveFile);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
