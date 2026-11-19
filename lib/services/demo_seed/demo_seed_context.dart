import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Demo veri üreticisinin tüm modül dosyalarında ortak kullandığı bağlam.
///
/// KURALLAR (her `demo_seed_<alan>.dart` dosyası uymak zorundadır):
///  * Yazılan HER doküman [DemoSeedContext.set] ile yazılmalıdır (isDemo + demoTag
///    alanlarını otomatik ekler). Doküman verisinde mutlaka `institutionId` alanı
///    bulunmalıdır (temizleme bu alanla sorgular).
///  * Doküman kimlikleri [DemoSeedContext.id] ile üretilmelidir (kuruma özel önek).
///  * Şifreli alanlara dokunulmaz; gerçek öğrenci/öğretmen kayıtları yazılmaz.
class DemoSeedContext {
  final FirebaseFirestore db;
  final String inst;

  /// Kuruma özel doküman kimliği öneki (örn. `dabc06_`).
  final String prefix;
  final String termId;
  final DateTime termStart;
  final DateTime today;
  final math.Random rng;
  final DemoBatchWriter w;

  /// `schools/{schoolDocId}` doküman kimliği (boş olabilir).
  final String schoolDocId;
  final List<DemoTypeDef> types;
  final List<DemoClassInfo> classes;
  final Map<String, List<DemoStudentInfo>> studentsByClass;
  final List<DemoTeacherInfo> teachers;
  final Map<String, int> counts;

  DemoSeedContext({
    required this.db,
    required this.inst,
    required this.prefix,
    required this.termId,
    required this.termStart,
    required this.today,
    required this.rng,
    required this.w,
    required this.schoolDocId,
    required this.types,
    required this.classes,
    required this.studentsByClass,
    required this.teachers,
    required this.counts,
  });

  /// Her demo dokümanına eklenen etiketler.
  Map<String, dynamic> get flag => const {
    'isDemo': true,
    'demoTag': 'edukn_demo_v1',
  };

  /// Kuruma özel doküman kimliği: `id('hw_1')` -> `dabc06_hw_1`.
  String id(String suffix) => '$prefix$suffix';

  /// Yazım sayacı (özet ekranında gösterilir).
  void count(String label, [int n = 1]) =>
      counts[label] = (counts[label] ?? 0) + n;

  /// Demo etiketlerini ekleyerek yazar.
  Future<void> set(DocumentReference ref, Map<String, dynamic> data) =>
      w.set(ref, {...data, ...flag});

  /// Üst düzey koleksiyona kısayol: `col('surveys').doc(id('s1'))`.
  CollectionReference<Map<String, dynamic>> col(String name) =>
      db.collection(name);

  /// `schools/{schoolDocId}/{name}` koleksiyonu (schoolDocId boşsa null).
  CollectionReference<Map<String, dynamic>>? schoolCol(String name) =>
      schoolDocId.isEmpty
      ? null
      : db.collection('schools').doc(schoolDocId).collection(name);

  /// Öğrencileri düz liste olarak döndürür.
  List<DemoStudentInfo> get allStudents =>
      studentsByClass.values.expand((e) => e).toList();

  /// Deterministik rastgele seçim yardımcıları.
  T pick<T>(List<T> list) => list[rng.nextInt(list.length)];
  int between(int minV, int maxV) => minV + rng.nextInt(maxV - minV + 1);
}

class DemoTeacherInfo {
  final String id;
  final String fullName;
  final String branch;
  final String typeId;
  final String typeName;
  const DemoTeacherInfo({
    required this.id,
    required this.fullName,
    required this.branch,
    required this.typeId,
    required this.typeName,
  });
}

class DemoTypeDef {
  final String id;
  final String kind;
  final String name;
  final List<int> levels;
  const DemoTypeDef({
    required this.id,
    required this.kind,
    required this.name,
    required this.levels,
  });
}

class DemoLessonInfo {
  final String id;
  final String name;
  final String shortName;
  final String branchId;
  final int weeklyHours;
  final String teacherId;
  final String teacherName;
  const DemoLessonInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.branchId,
    required this.weeklyHours,
    required this.teacherId,
    required this.teacherName,
  });
}

class DemoClassInfo {
  final String id;
  final String name;
  final int level;
  final String typeId;
  final String typeName;
  final String typeKind;
  final List<DemoLessonInfo> lessons;
  const DemoClassInfo({
    required this.id,
    required this.name,
    required this.level,
    required this.typeId,
    required this.typeName,
    required this.typeKind,
    required this.lessons,
  });
}

class DemoStudentInfo {
  final String id;
  final String no;
  final String fullName;
  final String tc;
  final String className;
  final String classId;
  final int level;
  final double ability;
  final Map<int, double> subjectOffsets;
  const DemoStudentInfo({
    required this.id,
    required this.no,
    required this.fullName,
    required this.tc,
    required this.className,
    required this.classId,
    required this.level,
    required this.ability,
    required this.subjectOffsets,
  });
}

/// 400'lük parçalar halinde Firestore batch yazıcı.
class DemoBatchWriter {
  final FirebaseFirestore db;
  WriteBatch _batch;
  int _pending = 0;
  int total = 0;

  DemoBatchWriter(this.db) : _batch = db.batch();

  Future<void> set(DocumentReference ref, Map<String, dynamic> data) async {
    _batch.set(ref, data);
    _pending++;
    total++;
    if (_pending >= 400) {
      await flush();
    }
  }

  Future<void> flush() async {
    if (_pending == 0) return;
    await _batch.commit();
    _batch = db.batch();
    _pending = 0;
  }
}
