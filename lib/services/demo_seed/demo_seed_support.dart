import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// DESTEK HİZMETLERİ demo verisi:
///  * Sağlık / Revir (healthVisits) + öğrenci hareketleri (geç kağıdı, çıkış izni,
///    veli erken alma, revir sevk) -> studentMovements
///  * Kitap listesi (books, book_assignments) ve Kütüphane (libraryBooks, bookLendings)
///  * Depo / Stok / Satın alma (warehouses, inventoryItems, stockTransactions,
///    materialRequests)
///  * Güvenlik kapısı ziyaretçi defteri (visitorLogs)

/// Yazılan üst düzey koleksiyonlar (hepsinde `institutionId` vardır).
const List<String> demoSupportTopCollections = ['books', 'book_assignments'];

/// `schools/{schoolDocId}/...` altında yazılan alt koleksiyonlar.
const List<String> demoSupportSchoolSubcollections = [
  'healthVisits',
  'studentMovements',
  'visitorLogs',
  'libraryBooks',
  'bookLendings',
  'warehouses',
  'inventoryItems',
  'stockTransactions',
  'materialRequests',
];

/// İç içe (listelerle ulaşılamayan) demo doküman yok.
Future<int> cleanDemoSupportExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Yardımcılar
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _maleNames = [
  'Ahmet',
  'Mehmet',
  'Mustafa',
  'Ali',
  'Hasan',
  'Murat',
  'Emre',
  'Burak',
  'Serkan',
  'Kemal',
];
const List<String> _femaleNames = [
  'Ayşe',
  'Fatma',
  'Zeynep',
  'Elif',
  'Hatice',
  'Merve',
  'Esra',
  'Selin',
  'Derya',
  'Gül',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Bugünden `back` gün önceki tarih (dönem başlangıcından önceye düşmez).
DateTime _termDay(DemoSeedContext ctx, int back) {
  final t = _dayOnly(ctx.today);
  var d = DateTime(t.year, t.month, t.day - back);
  final s = _dayOnly(ctx.termStart);
  if (d.isBefore(s)) d = s;
  return d;
}

/// Bugünden n iş günü öncesinin kaç gün geride olduğu (n=0 -> 0).
int _weekdayBack(DemoSeedContext ctx, int n) {
  final t = _dayOnly(ctx.today);
  var back = 0;
  var count = 0;
  while (count < n) {
    back++;
    final d = DateTime(t.year, t.month, t.day - back);
    if (d.weekday <= 5) count++;
    if (back > 400) break;
  }
  return back;
}

DateTime _at(DateTime day, int h, int m) =>
    DateTime(day.year, day.month, day.day, h, m);

String _normalizeTr(String input) {
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

String _phone(DemoSeedContext ctx) =>
    '05${ctx.between(30, 59)} ${ctx.between(100, 999)} ${_two(ctx.between(10, 99))} ${_two(ctx.between(10, 99))}';

String _plate(DemoSeedContext ctx) {
  const letters = ['ABC', 'KLM', 'YZT', 'DFG', 'HJK', 'MNP', 'RST', 'BCD'];
  final cities = [34, 6, 35, 16, 7, 41];
  return '${ctx.pick(cities)} ${ctx.pick(letters)} ${ctx.between(100, 999)}';
}

String _surname(String fullName) {
  final parts = fullName.trim().split(' ');
  return parts.isEmpty ? '' : parts.last;
}

String _parentName(DemoSeedContext ctx, DemoStudentInfo s) {
  final first = ctx.rng.nextBool()
      ? ctx.pick(_femaleNames)
      : ctx.pick(_maleNames);
  return '$first ${_surname(s.fullName)}';
}

const DemoTeacherInfo _fallbackTeacher = DemoTeacherInfo(
  id: '',
  fullName: 'Demo Öğretmen',
  branch: '',
  typeId: '',
  typeName: '',
);

// ─────────────────────────────────────────────────────────────────────────────
// Ana giriş noktası
// ─────────────────────────────────────────────────────────────────────────────

Future<void> seedDemoSupport(DemoSeedContext ctx) async {
  await _seedBooks(ctx);
  if (ctx.schoolDocId.isEmpty) return;
  await _seedHealthAndMovements(ctx);
  await _seedVisitors(ctx);
  await _seedLibrary(ctx);
  await _seedInventory(ctx);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1) SAĞLIK / REVİR + ÖĞRENCİ HAREKETLERİ
// ─────────────────────────────────────────────────────────────────────────────

class _Complaint {
  final String complaint;
  final String treatment;
  final String? medication;
  final String outcome;
  const _Complaint(
    this.complaint,
    this.treatment,
    this.medication,
    this.outcome,
  );
}

const String _oRest = 'Dinlendi, Derse Döndü';
const String _oObs = 'Gözlem Tamamlandı, Derse Döndü';
const String _oHome = 'Veli Bilgisiyle Eve Gönderildi';
const String _oRef = 'Sağlık Kuruluşuna Sevk Edildi';

const List<_Complaint> _complaints = [
  _Complaint('Baş ağrısı', 'Dinlendirildi, su içirildi', null, _oRest),
  _Complaint(
    'Karın ağrısı',
    'Revirde gözlem altında dinlendirildi',
    null,
    _oObs,
  ),
  _Complaint(
    'Ateş yüksekliği (37.9)',
    'Ateş ölçüldü, veli arandı',
    'Parasetamol (veli onaylı)',
    _oHome,
  ),
  _Complaint(
    'Düşme sonucu diz sıyrığı',
    'Pansuman / yara bakımı uygulandı',
    null,
    _oRest,
  ),
  _Complaint(
    'Burun kanaması',
    'Soğuk uygulama yapıldı, baş öne eğdirildi',
    null,
    _oObs,
  ),
  _Complaint(
    'Mide bulantısı',
    'Dinlendirildi, gözlem altında tutuldu',
    null,
    _oObs,
  ),
  _Complaint(
    'Bulantı ve halsizlik',
    'Ateş ve nabız kontrolü yapıldı',
    null,
    _oHome,
  ),
  _Complaint(
    'Spor dersinde ayak bileği burkulması',
    'Buz uygulaması, elastik bandaj',
    null,
    _oRef,
  ),
  _Complaint(
    'Diş ağrısı',
    'Veli bilgilendirildi, diş hekimine yönlendirme',
    'Ağrı kesici (veli onaylı)',
    _oHome,
  ),
  _Complaint(
    'Gözde kaşıntı ve kızarıklık',
    'Göz yıkandı, gözlem yapıldı',
    null,
    _oObs,
  ),
  _Complaint(
    'Kulak ağrısı',
    'Muayene edildi, veliye bilgi verildi',
    null,
    _oHome,
  ),
  _Complaint(
    'Alerjik döküntü',
    'Cilt kontrolü yapıldı, veli arandı',
    'Antihistaminik (veli onaylı)',
    _oRef,
  ),
  _Complaint('El parmağı sıkışması', 'Soğuk uygulama yapıldı', null, _oRest),
  _Complaint(
    'Baş dönmesi',
    'Yatırılarak dinlendirildi, tansiyon ölçüldü',
    null,
    _oRest,
  ),
  _Complaint('Boğaz ağrısı', 'Ateş ölçüldü, sıcak su verildi', null, _oRest),
];

Future<void> _seedHealthAndMovements(DemoSeedContext ctx) async {
  final students = ctx.allStudents;
  if (students.isEmpty) return;
  final healthCol = ctx.schoolCol('healthVisits')!;
  final moveCol = ctx.schoolCol('studentMovements')!;
  final teachers = ctx.teachers.isEmpty ? [_fallbackTeacher] : ctx.teachers;
  final classById = <String, DemoClassInfo>{
    for (final c in ctx.classes) c.id: c,
  };
  const nurse = 'Hemşire Aylin Demir';
  const bloods = ['A Rh+', '0 Rh+', 'B Rh+', 'AB Rh+', 'A Rh-', '0 Rh-'];

  var hv = 0;
  var mv = 0;

  // Revir ziyaretleri: bugün 5 (2'si açık), geçmiş iş günlerinde 2-3'er kayıt.
  final plan = <int>[]; // her kayıt için "kaç iş günü önce"
  plan.addAll(List<int>.filled(5, 0));
  for (var n = 1; n <= 14; n++) {
    plan.addAll(List<int>.filled(2 + (n % 2), n));
  }
  var openLeft = 2;
  for (var i = 0; i < plan.length; i++) {
    final s = ctx.pick(students);
    final cls = classById[s.classId];
    final c = ctx.pick(_complaints);
    final back = _weekdayBack(ctx, plan[i]);
    final day = _termDay(ctx, back);
    final hour = ctx.between(8, 15);
    final visitDate = _at(day, hour, ctx.between(0, 59));
    final isOpen = plan[i] == 0 && openLeft > 0;
    if (isOpen) openLeft--;
    final teacher = ctx.pick(teachers);
    final lessonHour = ctx.between(1, 7);
    String lessonId = '';
    String lessonName = '';
    if (cls != null && cls.lessons.isNotEmpty) {
      final l = ctx.pick(cls.lessons);
      lessonId = l.id;
      lessonName = l.name;
    }
    final urgency = ctx.rng.nextInt(10) == 0
        ? 'Acil'
        : (ctx.rng.nextInt(4) == 0 ? 'Öncelikli' : 'Normal');
    final visitId = ctx.id('hv_${hv++}');
    final movId = ctx.id('mov_${mv++}');
    final blood = ctx.pick(bloods);
    final parent = _parentName(ctx, s);
    final medGiven = c.medication != null && !isOpen;
    final completedAt = visitDate.add(Duration(minutes: ctx.between(15, 45)));

    await ctx.set(healthCol.doc(visitId), {
      'institutionId': ctx.inst,
      'studentId': s.id,
      'studentNo': s.no,
      'classId': s.classId,
      'className': s.className,
      'bloodType': blood,
      'studentName': '${s.fullName} (${s.className})',
      'complaint': c.complaint,
      'treatment': isOpen ? '' : c.treatment,
      'medicationGiven': medGiven,
      'medicationName': medGiven ? c.medication : '',
      'notes': isOpen
          ? ''
          : (c.outcome == _oHome || c.outcome == _oRef
                ? 'Veli ($parent) telefonla bilgilendirildi.'
                : 'Öğrenci genel durumu iyi, derse yönlendirildi.'),
      'visitDate': Timestamp.fromDate(visitDate),
      'createdAt': Timestamp.fromDate(visitDate),
      'createdBy': teacher.fullName,
      'schoolTypeId': cls?.typeId ?? '',
      'visitStatus': isOpen ? 'open' : 'completed',
      'urgency': urgency,
      'referralMovementId': movId,
      'referredByUid': teacher.id,
      'referredByName': teacher.fullName,
      'referredByRole': 'teacher',
      'lessonHour': lessonHour,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'targetTeacherIds': [teacher.id],
      'targetTeacherNames': [teacher.fullName],
      'parentNotified': !isOpen && (c.outcome == _oHome || c.outcome == _oRef),
      if (!isOpen) 'outcome': c.outcome,
      if (!isOpen) 'handledByUid': '',
      if (!isOpen) 'handledByName': nurse,
      if (!isOpen) 'completedAt': Timestamp.fromDate(completedAt),
    });
    ctx.count('Revir ziyareti');

    await ctx.set(
      moveCol.doc(movId),
      _movementMap(
        ctx,
        s: s,
        cls: cls,
        teacher: teacher,
        type: 'infirmary',
        status: isOpen ? 'in_infirmary' : 'completed',
        day: day,
        createdAt: visitDate,
        lessonHour: lessonHour,
        lessonId: lessonId,
        lessonName: lessonName,
        reason: c.complaint,
        urgency: urgency,
        parentName: parent,
        blood: blood,
        extra: {
          'healthVisitId': visitId,
          'infirmaryTreatment': isOpen ? '' : c.treatment,
          'medicationGiven': medGiven,
          'medicationName': medGiven ? c.medication : '',
          'infirmaryOutcome': isOpen ? '' : c.outcome,
          'handledByInfirmaryName': isOpen ? '' : nurse,
          'completedAt': isOpen ? null : Timestamp.fromDate(completedAt),
        },
      ),
    );
    ctx.count('Öğrenci hareketi');
  }

  // Geç kağıtları (14 adet)
  const lateReasons = [
    'Servis gecikmesi',
    'Doktor randevusu',
    'Trafik yoğunluğu',
    'Uyuyakalma / ailevi neden',
    'Yağmurlu hava nedeniyle ulaşım sorunu',
  ];
  for (var i = 0; i < 14; i++) {
    final s = ctx.pick(students);
    final cls = classById[s.classId];
    final teacher = ctx.pick(teachers);
    final day = _termDay(ctx, _weekdayBack(ctx, i % 10));
    final created = _at(day, 8, ctx.between(35, 59));
    String lessonId = '';
    String lessonName = '';
    if (cls != null && cls.lessons.isNotEmpty) {
      final l = ctx.pick(cls.lessons);
      lessonId = l.id;
      lessonName = l.name;
    }
    await ctx.set(
      moveCol.doc(ctx.id('mov_${mv++}')),
      _movementMap(
        ctx,
        s: s,
        cls: cls,
        teacher: teacher,
        type: 'late',
        status: 'issued_late',
        day: day,
        createdAt: created,
        lessonHour: 1,
        lessonId: lessonId,
        lessonName: lessonName,
        reason: ctx.pick(lateReasons),
        urgency: 'Normal',
        parentName: _parentName(ctx, s),
        blood: '',
        extra: {'notes': 'Geç kağıdı düzenlendi, 1. derse yönlendirildi.'},
      ),
    );
    ctx.count('Öğrenci hareketi');
  }

  // Çıkış izinleri (veli eşliğinde, güvenlik onaylı) - 9 geçmiş + 1 bugün bekleyen
  const exitReasons = [
    'Hastane randevusu',
    'Ailevi zorunluluk',
    'Diş hekimi kontrolü',
    'Resmi işlem / nüfus müdürlüğü',
    'Sınav (dış kurum) katılımı',
  ];
  const securityName = 'Güvenlik Görevlisi Recep Arslan';
  for (var i = 0; i < 10; i++) {
    final s = ctx.pick(students);
    final cls = classById[s.classId];
    final teacher = ctx.pick(teachers);
    final today = i == 9;
    final day = _termDay(ctx, today ? 0 : _weekdayBack(ctx, 1 + i));
    final created = _at(day, ctx.between(9, 13), ctx.between(0, 59));
    final parent = _parentName(ctx, s);
    final hour = ctx.between(3, 6);
    await ctx.set(
      moveCol.doc(ctx.id('mov_${mv++}')),
      _movementMap(
        ctx,
        s: s,
        cls: cls,
        teacher: teacher,
        type: 'exit_permission',
        status: today ? 'pending_gate' : 'exited_school',
        day: day,
        createdAt: created,
        lessonHour: hour,
        lessonId: '',
        lessonName: '',
        reason: ctx.pick(exitReasons),
        urgency: 'Normal',
        parentName: parent,
        blood: '',
        extra: {
          'exitMode': 'Veli Eşliğinde',
          'receiverName': parent,
          'receiverRelation': ctx.rng.nextBool() ? 'Anne' : 'Baba',
          'receiverPhone': _phone(ctx),
          'vehiclePlate': _plate(ctx),
          'plannedExitTime': '${_two(created.hour)}:${_two(created.minute)}',
          'autoExcusedHours': today ? <int>[] : [hour, hour + 1, hour + 2],
          if (!today)
            'gateApprovedAt': Timestamp.fromDate(
              created.add(const Duration(minutes: 12)),
            ),
          if (!today) 'gateApprovedByUid': '',
          if (!today) 'gateApprovedByName': securityName,
          if (!today) 'gateNote': 'Veli kimlik kontrolü yapıldı.',
          if (!today)
            'completedAt': Timestamp.fromDate(
              created.add(const Duration(minutes: 12)),
            ),
        },
      ),
    );
    ctx.count('Öğrenci hareketi');
  }

  // Veli erken alma: 6 tamamlanmış + bugün (bildirildi 2, veli geldi 1)
  for (var i = 0; i < 9; i++) {
    final s = ctx.pick(students);
    final cls = classById[s.classId];
    final teacher = ctx.pick(teachers);
    final todayRec = i >= 6;
    final day = _termDay(ctx, todayRec ? 0 : _weekdayBack(ctx, 2 + i));
    final planned = ctx.between(11, 15);
    final created = _at(day, 8, ctx.between(0, 40));
    final parent = _parentName(ctx, s);
    var status = 'exited_school';
    if (todayRec) {
      status = i == 8 ? 'parent_arrived' : 'early_pickup_notified';
    }
    final done = status == 'exited_school';
    final arrived = _at(day, planned, ctx.between(0, 20));
    await ctx.set(
      moveCol.doc(ctx.id('mov_${mv++}')),
      _movementMap(
        ctx,
        s: s,
        cls: cls,
        teacher: teacher,
        type: 'early_pickup',
        status: status,
        day: day,
        createdAt: created,
        lessonHour: planned - 7,
        lessonId: '',
        lessonName: '',
        reason: ctx.pick(exitReasons),
        urgency: 'Normal',
        parentName: parent,
        blood: '',
        extra: {
          'exitMode': 'Veli Erken Alma',
          'receiverName': parent,
          'receiverRelation': ctx.rng.nextBool() ? 'Anne' : 'Baba',
          'receiverPhone': _phone(ctx),
          'vehiclePlate': _plate(ctx),
          'plannedExitTime': '${_two(planned)}:00',
          'requestSource': 'parent_portal',
          if (status != 'early_pickup_notified')
            'parentArrivedAt': Timestamp.fromDate(arrived),
          if (done)
            'gateApprovedAt': Timestamp.fromDate(
              arrived.add(const Duration(minutes: 10)),
            ),
          if (done) 'gateApprovedByName': securityName,
          if (done) 'gateNote': 'Öğrenci veliye teslim edildi.',
          if (done)
            'completedAt': Timestamp.fromDate(
              arrived.add(const Duration(minutes: 10)),
            ),
          if (done) 'autoExcusedHours': [planned - 6, planned - 5, planned - 4],
        },
      ),
    );
    ctx.count('Veli erken alma');
  }
}

Map<String, dynamic> _movementMap(
  DemoSeedContext ctx, {
  required DemoStudentInfo s,
  required DemoClassInfo? cls,
  required DemoTeacherInfo teacher,
  required String type,
  required String status,
  required DateTime day,
  required DateTime createdAt,
  required int lessonHour,
  required String lessonId,
  required String lessonName,
  required String reason,
  required String urgency,
  required String parentName,
  required String blood,
  required Map<String, dynamic> extra,
}) {
  final base = <String, dynamic>{
    'institutionId': ctx.inst,
    'schoolDocId': ctx.schoolDocId,
    'schoolTypeId': cls?.typeId ?? '',
    'schoolTypeName': cls?.typeName ?? '',
    'dateStr': _ymd(day),
    'type': type,
    'status': status,
    'studentId': s.id,
    'studentName': s.fullName,
    'studentNo': s.no,
    'classId': s.classId,
    'className': s.className,
    'bloodType': blood,
    'parentName': parentName,
    'parentPhone': _phone(ctx),
    'lessonHour': lessonHour < 1 ? 1 : lessonHour,
    'coveredLessonHours': <int>[],
    'lessonId': lessonId,
    'lessonName': lessonName,
    'lessonStartTime': '',
    'lessonEndTime': '',
    'targetTeacherIds': [teacher.id],
    'targetTeacherNames': [teacher.fullName],
    'reason': reason,
    'notes': '',
    'urgency': urgency,
    'exitMode': '',
    'receiverName': '',
    'receiverRelation': '',
    'receiverPhone': '',
    'vehiclePlate': '',
    'plannedExitTime': '',
    'parentArrivedAt': null,
    'requestSource': 'school_admin',
    'gateApprovedAt': null,
    'gateApprovedByUid': '',
    'gateApprovedByName': '',
    'gateNote': '',
    'autoExcusedHours': <int>[],
    'healthVisitId': '',
    'infirmaryTreatment': '',
    'medicationGiven': false,
    'medicationName': '',
    'infirmaryOutcome': '',
    'handledByInfirmaryName': '',
    'interviewUnit': '',
    'interviewerName': '',
    'protectAttendance': true,
    'createdByUid': teacher.id,
    'createdByName': teacher.fullName,
    'createdByRole': 'teacher',
    'createdAt': Timestamp.fromDate(createdAt),
    'completedAt': null,
  };
  base.addAll(extra);
  return base;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) GÜVENLİK: ZİYARETÇİ DEFTERİ
// ─────────────────────────────────────────────────────────────────────────────

class _VisitorTpl {
  final String category;
  final String unit;
  final String reason;
  final String relation;
  const _VisitorTpl(this.category, this.unit, this.reason, this.relation);
}

const List<_VisitorTpl> _visitorTpls = [
  _VisitorTpl(
    'Öğrenci Velisi / Yakını',
    'Okul İdaresi (Müdür / Müdür Yardımcısı)',
    'Veli Görüşmesi / Öğrenci Durum Bilgisi',
    'Veli',
  ),
  _VisitorTpl(
    'Öğrenci Velisi / Yakını',
    'Rehberlik / PDR Servisi',
    'Veli Görüşmesi / Öğrenci Durum Bilgisi',
    'Veli',
  ),
  _VisitorTpl(
    'Kayıt / Tanıtım Görüşmesi (Aday Veli)',
    'Muhasebe / Öğrenci İşleri / Kayıt Kabul',
    'Yeni Kayıt / Okul Tanıtım Görüşmesi',
    'Aday Veli',
  ),
  _VisitorTpl(
    'Resmi Kurum Görevlisi / Denetmen',
    'Okul İdaresi (Müdür / Müdür Yardımcısı)',
    'Randevulu Kurum / İdare Ziyareti',
    'İlçe Milli Eğitim Müdürlüğü',
  ),
  _VisitorTpl(
    'Kargo / Tedarikçi / Teknik Servis',
    'Destek Hizmetleri / Teknik Birim / Depo',
    'Kargo / Malzeme Teslimatı / Teknik Bakım',
    'Hızlı Kargo A.Ş.',
  ),
  _VisitorTpl(
    'Kargo / Tedarikçi / Teknik Servis',
    'Destek Hizmetleri / Teknik Birim / Depo',
    'Kargo / Malzeme Teslimatı / Teknik Bakım',
    'Yıldız Kırtasiye Toptan',
  ),
  _VisitorTpl(
    'Mezun / Misafir / Diğer Ziyaretçi',
    'Öğretmen Görüşmesi',
    'Evrak / Resmi Belge Teslimi',
    'Mezun',
  ),
  _VisitorTpl(
    'Öğrenci Velisi / Yakını',
    'Öğretmen Görüşmesi',
    'Veli Görüşmesi / Öğrenci Durum Bilgisi',
    'Veli',
  ),
];

Future<void> _seedVisitors(DemoSeedContext ctx) async {
  final col = ctx.schoolCol('visitorLogs')!;
  final teachers = ctx.teachers.isEmpty ? [_fallbackTeacher] : ctx.teachers;
  const guard = 'Güvenlik Görevlisi Recep Arslan';
  const names = [
    'Hülya Kaya',
    'Osman Çelik',
    'Nurten Aydın',
    'Cengiz Polat',
    'Sevgi Yurt',
    'Tamer Güneş',
    'Pınar Özkan',
    'Volkan Erdem',
    'Gamze Taş',
    'Barış Koç',
    'Leyla Şahin',
    'İbrahim Aksoy',
  ];
  var n = 0;
  // Bugün: 4 kayıt (2'si içeride), geçmiş 9 iş gününde 2-3'er kayıt.
  final plan = <int>[0, 0, 0, 0];
  for (var d = 1; d <= 9; d++) {
    plan.addAll(List<int>.filled(2 + (d % 2), d));
  }
  var insideLeft = 2;
  for (final wd in plan) {
    final tpl = ctx.pick(_visitorTpls);
    final day = _termDay(ctx, _weekdayBack(ctx, wd));
    final entry = _at(day, ctx.between(8, 15), ctx.between(0, 59));
    final inside = wd == 0 && insideLeft > 0;
    if (inside) insideLeft--;
    final exit = entry.add(Duration(minutes: ctx.between(10, 70)));
    final host = ctx.pick(teachers);
    final hasVehicle =
        tpl.category.startsWith('Kargo') || ctx.rng.nextInt(4) == 0;
    await ctx.set(col.doc(ctx.id('visitor_${n++}')), {
      'institutionId': ctx.inst,
      'schoolDocId': ctx.schoolDocId,
      'schoolTypeId': '',
      'schoolTypeName': '',
      'dateStr': _ymd(day),
      'status': inside ? 'inside' : 'exited',
      'visitorName': ctx.pick(names),
      'visitorCategory': tpl.category,
      'visitorPhone': _phone(ctx),
      'identityCheckInfo': 'Kimlik kontrol edildi',
      'badgeNo': 'Z-${ctx.between(1, 40)}',
      'vehiclePlate': hasVehicle ? _plate(ctx) : '',
      'companyOrRelation': tpl.relation,
      'targetUnit': tpl.unit,
      'hostStaffUid': host.id,
      'hostStaffName': host.fullName,
      'visitReason': tpl.reason,
      'entryNote': '',
      'exitNote': inside ? '' : 'Görüşme tamamlandı.',
      'entryTime': Timestamp.fromDate(entry),
      'exitTime': inside ? null : Timestamp.fromDate(exit),
      'checkedInByUid': '',
      'checkedInByName': guard,
      'checkedOutByUid': '',
      'checkedOutByName': inside ? '' : guard,
    });
    ctx.count('Ziyaretçi kaydı');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) KİTAP LİSTESİ (books / book_assignments)
// ─────────────────────────────────────────────────────────────────────────────

class _ReadingBook {
  final String name;
  final String author;
  final int pages;
  const _ReadingBook(this.name, this.author, this.pages);
}

const List<_ReadingBook> _readingBooks = [
  _ReadingBook('Küçük Prens', 'Antoine de Saint-Exupéry', 96),
  _ReadingBook('Çalıkuşu', 'Reşat Nuri Güntekin', 432),
  _ReadingBook('Sefiller (Gençler İçin)', 'Victor Hugo', 280),
  _ReadingBook('Simyacı', 'Paulo Coelho', 184),
  _ReadingBook('Kuyucaklı Yusuf', 'Sabahattin Ali', 208),
  _ReadingBook('Tom Sawyer\'ın Maceraları', 'Mark Twain', 224),
  _ReadingBook('Dokuzuncu Hariciye Koğuşu', 'Peyami Safa', 136),
  _ReadingBook('Hayvan Çiftliği', 'George Orwell', 152),
  _ReadingBook('Beyaz Diş', 'Jack London', 256),
  _ReadingBook('Tosbağa Terbiyecisi', 'Osman Hamdi Bey', 120),
  _ReadingBook('Çanakkale Çocukları', 'Hikmet Dede', 144),
  _ReadingBook('Momo', 'Michael Ende', 304),
];

class _QBank {
  final String name;
  final String branch;
  final List<String> topics;
  const _QBank(this.name, this.branch, this.topics);
}

const List<_QBank> _qBanks = [
  _QBank('Matematik Soru Bankası', 'Matematik', [
    'Doğal Sayılar',
    'Kesirler',
    'Ondalık Gösterim',
    'Yüzdeler',
  ]),
  _QBank('Fen Bilimleri Soru Bankası', 'Fen Bilimleri', [
    'Kuvvet ve Hareket',
    'Maddenin Yapısı',
    'Işık ve Ses',
  ]),
  _QBank('Türkçe Paragraf Soru Bankası', 'Türkçe', [
    'Sözcükte Anlam',
    'Cümlede Anlam',
    'Paragraf',
  ]),
  _QBank('Sosyal Bilgiler Soru Bankası', 'Sosyal Bilgiler', [
    'Birey ve Toplum',
    'Kültür ve Miras',
    'Üretim, Dağıtım, Tüketim',
  ]),
  _QBank('İngilizce Kelime ve Dil Bilgisi', 'İngilizce', [
    'Tenses',
    'Vocabulary',
    'Reading',
  ]),
  _QBank('Geometri Soru Bankası', 'Matematik', [
    'Açılar',
    'Üçgenler',
    'Dörtgenler',
  ]),
];

Future<void> _seedBooks(DemoSeedContext ctx) async {
  final booksCol = ctx.col('books');
  final assignCol = ctx.col('book_assignments');
  final levelSet = <int>{};
  for (final c in ctx.classes) {
    levelSet.add(c.level);
  }
  var levels = levelSet.toList()..sort();
  if (levels.isEmpty) levels = [5, 6, 7, 8];
  final rng = ctx.rng;
  final bookIds = <String>[];
  final bookNames = <String>[];

  var i = 0;
  for (final b in _readingBooks) {
    final id = ctx.id('book_${i++}');
    final lv = levels[rng.nextInt(levels.length)];
    final lvls = <String>{
      lv.toString(),
      if (levels.contains(lv + 1)) (lv + 1).toString(),
    }.toList();
    await ctx.set(booksCol.doc(id), {
      'institutionId': ctx.inst,
      'name': b.name,
      'type': 'reading',
      'author': b.author,
      'pageCount': b.pages,
      'branch': null,
      'classLevels': lvls,
      'topics': <Map<String, dynamic>>[],
      'isActive': true,
      'createdAt': Timestamp.fromDate(
        _at(_termDay(ctx, ctx.between(5, 50)), 10, 0),
      ),
    });
    bookIds.add(id);
    bookNames.add(b.name);
    ctx.count('Kitap');
  }

  for (final q in _qBanks) {
    final id = ctx.id('book_${i++}');
    final topics = <Map<String, dynamic>>[];
    var t = 0;
    for (final tn in q.topics) {
      final hasSub = t == 0;
      topics.add({
        'id': ctx.id('topic_${i}_$t'),
        'name': tn,
        'testCount': hasSub ? null : ctx.between(4, 10),
        'questionsPerTest': hasSub ? null : 12,
        'questionsPerTestList': null,
        'subtopics': hasSub
            ? [
                {
                  'id': ctx.id('sub_${i}_${t}_a'),
                  'name': '$tn - Temel',
                  'testCount': ctx.between(3, 6),
                  'questionsPerTest': 10,
                  'questionsPerTestList': null,
                },
                {
                  'id': ctx.id('sub_${i}_${t}_b'),
                  'name': '$tn - Gelişmiş',
                  'testCount': ctx.between(3, 6),
                  'questionsPerTest': 12,
                  'questionsPerTestList': null,
                },
              ]
            : <Map<String, dynamic>>[],
      });
      t++;
    }
    final lv = levels[rng.nextInt(levels.length)];
    await ctx.set(booksCol.doc(id), {
      'institutionId': ctx.inst,
      'name': q.name,
      'type': 'questionBank',
      'author': null,
      'pageCount': null,
      'branch': q.branch,
      'classLevels': [lv.toString()],
      'topics': topics,
      'isActive': true,
      'createdAt': Timestamp.fromDate(
        _at(_termDay(ctx, ctx.between(5, 50)), 11, 0),
      ),
    });
    bookIds.add(id);
    bookNames.add(q.name);
    ctx.count('Kitap');
  }

  // Atamalar
  var a = 0;
  Future<void> assign(
    int bookIdx,
    String targetType,
    String targetId,
    String targetName,
  ) async {
    await ctx.set(assignCol.doc(ctx.id('bassign_${a++}')), {
      'institutionId': ctx.inst,
      'bookId': bookIds[bookIdx % bookIds.length],
      'targetType': targetType,
      'targetId': targetId,
      'targetName': targetName,
      'assignedAt': Timestamp.fromDate(
        _at(_termDay(ctx, ctx.between(2, 40)), 9, ctx.between(0, 59)),
      ),
    });
    ctx.count('Kitap ataması');
  }

  if (ctx.types.isNotEmpty) {
    await assign(0, 'schoolType', ctx.types.first.id, ctx.types.first.name);
  }
  for (var k = 0; k < levels.length && k < 4; k++) {
    await assign(
      k + 1,
      'classLevel',
      levels[k].toString(),
      '${levels[k]}. Sınıf Seviyesi',
    );
  }
  for (var k = 0; k < ctx.classes.length && k < 6; k++) {
    final c = ctx.classes[k];
    await assign(k + 3, 'className', c.id, c.name);
  }
  final students = ctx.allStudents;
  for (var k = 0; k < 8 && students.isNotEmpty; k++) {
    final s = ctx.pick(students);
    await assign(
      ctx.between(0, bookIds.length - 1),
      'student',
      s.id,
      s.fullName,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4) KÜTÜPHANE (libraryBooks / bookLendings)
// ─────────────────────────────────────────────────────────────────────────────

class _LibBook {
  final String title;
  final String author;
  final String category;
  const _LibBook(this.title, this.author, this.category);
}

const List<_LibBook> _libBooks = [
  _LibBook('Kürk Mantolu Madonna', 'Sabahattin Ali', 'Roman'),
  _LibBook(
    'Sherlock Holmes: Kızıl Soruşturma',
    'Arthur Conan Doyle',
    'Polisiye',
  ),
  _LibBook('Harry Potter ve Felsefe Taşı', 'J.K. Rowling', 'Fantastik'),
  _LibBook('Nutuk', 'Mustafa Kemal Atatürk', 'Tarih'),
  _LibBook('Bir Bilim Adamının Romanı', 'Ahmet Ağaoğlu', 'Biyografi'),
  _LibBook('Kâşiften Dünyaya', 'Ayşe Gürsoy', 'Bilim'),
  _LibBook('Uzay Yolculuğu Atlası', 'Mehmet Aydın', 'Bilim'),
  _LibBook('Çocuklar İçin Dünya Tarihi', 'Esin Yılmaz', 'Tarih'),
  _LibBook('Pollyanna', 'Eleanor H. Porter', 'Roman'),
  _LibBook('Define Adası', 'Robert L. Stevenson', 'Macera'),
  _LibBook(
    'Yüzüklerin Efendisi: Yüzük Kardaşlığı',
    'J.R.R. Tolkien',
    'Fantastik',
  ),
  _LibBook('Şermin', 'Orhan Veli', 'Şiir'),
  _LibBook('Türk Masalları', 'Pertev Naili Boratav', 'Masal'),
  _LibBook('İstanbul Hatırası', 'Ahmet Ümit', 'Polisiye'),
  _LibBook('Küçük Kara Balık', 'Samed Behrengi', 'Hikaye'),
  _LibBook('Matematik Neden Güzeldir?', 'Cengiz Tuna', 'Bilim'),
  _LibBook('Gulliver\'in Gezileri', 'Jonathan Swift', 'Macera'),
  _LibBook('Heidi', 'Johanna Spyri', 'Roman'),
  _LibBook('Robinson Crusoe', 'Daniel Defoe', 'Macera'),
  _LibBook('Atatürk\'ün Hayatı', 'Falih Rıfkı Atay', 'Biyografi'),
  _LibBook('Ses Bayrağı', 'Nazım Hikmet', 'Şiir'),
  _LibBook('Dünyayı Değiştiren Kadınlar', 'Nilay Demir', 'Biyografi'),
  _LibBook('Hz. Mevlana\'dan Hikayeler', 'Kolektif', 'Hikaye'),
  _LibBook('Hayat Bilgisi Ansiklopedisi', 'Kolektif', 'Ansiklopedi'),
];

Future<void> _seedLibrary(DemoSeedContext ctx) async {
  final booksCol = ctx.schoolCol('libraryBooks')!;
  final lendCol = ctx.schoolCol('bookLendings')!;
  final students = ctx.allStudents;
  final types = ctx.types;

  final qty = <int>[];
  final typeOf = <String>[];
  for (var i = 0; i < _libBooks.length; i++) {
    qty.add(ctx.between(2, 6));
    typeOf.add(types.isEmpty ? '' : types[i % types.length].id);
  }
  final active = List<int>.filled(_libBooks.length, 0);

  final lendings = <Map<String, dynamic>>[];
  if (students.isNotEmpty) {
    // 6 gecikmiş, 8 süresi dolmamış aktif, 16 iade edilmiş
    for (var k = 0; k < 30; k++) {
      final bi = ctx.between(0, _libBooks.length - 1);
      final s = ctx.pick(students);
      final kind = k < 6 ? 'overdue' : (k < 14 ? 'active' : 'returned');
      if (kind != 'returned' && active[bi] >= qty[bi]) continue;
      late int backDays;
      switch (kind) {
        case 'overdue':
          backDays = ctx.between(18, 40);
          break;
        case 'active':
          backDays = ctx.between(1, 10);
          break;
        default:
          backDays = ctx.between(10, 45);
      }
      final lendDate = _at(
        _termDay(ctx, backDays),
        ctx.between(9, 15),
        ctx.between(0, 59),
      );
      final due = lendDate.add(const Duration(days: 14));
      if (kind != 'returned') active[bi]++;
      lendings.add({
        'institutionId': ctx.inst,
        'bookId': ctx.id('lib_$bi'),
        'bookTitle': _libBooks[bi].title,
        'studentName': '${s.fullName} (${s.className})',
        'studentId': s.id,
        'lendDate': Timestamp.fromDate(lendDate),
        'dueDate': Timestamp.fromDate(due),
        'returned': kind == 'returned',
        'returnDate': kind == 'returned'
            ? Timestamp.fromDate(
                lendDate.add(Duration(days: ctx.between(5, 14))),
              )
            : null,
        'createdAt': Timestamp.fromDate(lendDate),
        'schoolTypeId': typeOf[bi],
      });
    }
  }

  for (var i = 0; i < _libBooks.length; i++) {
    final b = _libBooks[i];
    final available = qty[i] - active[i];
    await ctx.set(booksCol.doc(ctx.id('lib_$i')), {
      'institutionId': ctx.inst,
      'title': b.title,
      'author': b.author,
      'isbn': '978605${ctx.between(100000, 999999)}${ctx.between(0, 9)}',
      'category': b.category,
      'quantity': qty[i],
      'available': available < 0 ? 0 : available,
      'createdAt': Timestamp.fromDate(
        _at(_termDay(ctx, ctx.between(30, 60)), 10, 0),
      ),
      'schoolTypeId': typeOf[i],
    });
    ctx.count('Kütüphane kitabı');
  }
  var li = 0;
  for (final l in lendings) {
    await ctx.set(lendCol.doc(ctx.id('lend_${li++}')), l);
    ctx.count('Ödünç kaydı');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5) DEPO / STOK / SATIN ALMA
// ─────────────────────────────────────────────────────────────────────────────

class _Item {
  final String name;
  final String category;
  final String unit;
  final double price;
  final double min;
  final double qty;
  final int w; // 0 merkez, 1 ilk okul türü deposu, 2 ikinci okul türü deposu
  const _Item(
    this.name,
    this.category,
    this.unit,
    this.price,
    this.min,
    this.qty, [
    this.w = 0,
  ]);
}

const String _cOffice = 'Kırtasiye & Ofis';
const String _cClean = 'Temizlik & Hijyen';
const String _cIt = 'Bilişim & Elektronik';
const String _cLab = 'Laboratuvar & Fen';
const String _cSport = 'Spor & Etkinlik';
const String _cKitchen = 'Yemek & Mutfak';
const String _cRepair = 'Bakım & Onarım';
const String _cFurn = 'Mobilya & Demirbaş';
const String _cHealth = 'Sağlık / Revir Malzemesi';

const List<_Item> _items = [
  _Item('A4 Fotokopi Kağıdı (5\'li Koli)', _cOffice, 'Koli', 285, 10, 34),
  _Item('Tahta Kalemi - Siyah', _cOffice, 'Kutu', 120, 15, 8),
  _Item('Tahta Kalemi - Mavi', _cOffice, 'Kutu', 120, 10, 22),
  _Item('Keçeli Kalem Seti', _cOffice, 'Paket', 65, 10, 40, 1),
  _Item('Dosya Klasörü', _cOffice, 'Adet', 22, 30, 140),
  _Item('Zımba Teli', _cOffice, 'Kutu', 18, 20, 12),
  _Item('Yazıcı Toneri', _cIt, 'Adet', 1850, 3, 2),
  _Item('HDMI Kablo (3 m)', _cIt, 'Adet', 140, 5, 11),
  _Item('Çamaşır Suyu 5 L', _cClean, 'Adet', 95, 12, 26),
  _Item('Yüzey Temizleyici', _cClean, 'Litre', 70, 10, 5),
  _Item('Tuvalet Kağıdı (48\'li)', _cClean, 'Koli', 410, 6, 14),
  _Item('Sıvı Sabun 5 L', _cClean, 'Adet', 130, 10, 0),
  _Item('Çöp Torbası Jumbo', _cClean, 'Paket', 55, 20, 64),
  _Item('Kağıt Havlu', _cClean, 'Koli', 360, 5, 9),
  _Item('El Dezenfektanı', _cClean, 'Litre', 85, 10, 31),
  _Item('Steril Gazlı Bez', _cHealth, 'Kutu', 45, 10, 18),
  _Item('Ağrı Kesici (Parasetamol)', _cHealth, 'Kutu', 38, 5, 7),
  _Item('Yara Bandı', _cHealth, 'Kutu', 30, 10, 25),
  _Item('Ateş Ölçer (Temassız)', _cHealth, 'Adet', 420, 2, 3),
  _Item('Buz Aküsü', _cHealth, 'Adet', 55, 6, 4),
  _Item('Basketbol Topu No:6', _cSport, 'Adet', 780, 4, 9, 1),
  _Item('Voleybol Topu', _cSport, 'Adet', 650, 4, 6, 1),
  _Item('Atlama İpi', _cSport, 'Adet', 60, 10, 18),
  _Item('Mikroskop Lamı', _cLab, 'Kutu', 110, 5, 14, 2),
  _Item('Laboratuvar Eldiveni', _cLab, 'Kutu', 160, 5, 3, 2),
  _Item('Beher 250 ml', _cLab, 'Adet', 85, 10, 27, 2),
  _Item('Tek Kullanımlık Bardak', _cKitchen, 'Koli', 190, 5, 11),
  _Item('Peçete', _cKitchen, 'Koli', 210, 5, 7),
  _Item('LED Ampul 12W', _cRepair, 'Adet', 48, 20, 75),
  _Item('Tornavida / Vida Seti', _cRepair, 'Takım', 240, 2, 4),
  _Item('Öğrenci Sandalyesi', _cFurn, 'Adet', 1450, 5, 12),
];

const List<String> _suppliers = [
  'Yıldız Kırtasiye Toptan',
  'Anadolu Ofis Ürünleri Ltd. Şti.',
  'Temiz Dünya Hijyen A.Ş.',
  'Bilişim Plus Teknoloji',
  'Sağlık-Med Medikal',
  'Sporland Spor Malzemeleri',
  'Merkez Teknik Market',
];

class _Op {
  final int back;
  final String type; // in | out
  final double qty;
  final String recipient;
  final String note;
  const _Op(this.back, this.type, this.qty, this.recipient, this.note);
}

Future<void> _seedInventory(DemoSeedContext ctx) async {
  final whCol = ctx.schoolCol('warehouses')!;
  final itemCol = ctx.schoolCol('inventoryItems')!;
  final txCol = ctx.schoolCol('stockTransactions')!;
  final reqCol = ctx.schoolCol('materialRequests')!;
  final teachers = ctx.teachers.isEmpty ? [_fallbackTeacher] : ctx.teachers;
  const keeper = 'Depo Sorumlusu Hasan Yıldırım';

  // Depolar
  final whIds = <String>[];
  final whNames = <String>[];
  final whTypeIds = <String>[];
  final whTypeNames = <String>[];
  Future<void> addWh(
    String name,
    String typeId,
    String typeName,
    String loc,
  ) async {
    final id = ctx.id('wh_${whIds.length}');
    final central = typeId.isEmpty;
    await ctx.set(whCol.doc(id), {
      'institutionId': ctx.inst,
      'schoolDocId': ctx.schoolDocId,
      'name': name,
      'type': central ? 'central' : 'schoolType',
      'schoolTypeId': typeId,
      'schoolTypeName': typeName,
      'location': loc,
      'responsibleUserIds': <String>[],
      'responsibleNames': [keeper],
      'isActive': true,
      'createdAt': Timestamp.fromDate(_at(_termDay(ctx, 60), 9, 0)),
    });
    whIds.add(id);
    whNames.add(name);
    whTypeIds.add(typeId);
    whTypeNames.add(typeName);
    ctx.count('Depo');
  }

  await addWh('Merkez Ana Depo', '', '', 'Ana Bina - Zemin Kat');
  for (var i = 0; i < ctx.types.length && i < 2; i++) {
    final t = ctx.types[i];
    await addWh(
      '${t.name} Deposu',
      t.id,
      t.name,
      '${t.name} Binası - Depo Odası',
    );
  }

  // Stok kartları + hareketler
  final itemIds = <String>[];
  final itemWh = <int>[];
  var tn = 0;
  for (var i = 0; i < _items.length; i++) {
    final it = _items[i];
    final w = it.w < whIds.length ? it.w : 0;
    final id = ctx.id('item_$i');
    itemIds.add(id);
    itemWh.add(w);

    // Hareket planı: 1-3 çıkış, bazen bir giriş; başlangıç stoğu bunlara göre hesaplanır.
    final ops = <_Op>[];
    var outs = 0.0;
    var ins = 0.0;
    final outCount = it.qty <= 0 ? 1 : ctx.between(1, 3);
    for (var k = 0; k < outCount; k++) {
      final q = (ctx.between(1, 4) * (it.price > 1000 ? 1 : 2)).toDouble();
      outs += q;
      final r = ctx.pick(teachers);
      ops.add(
        _Op(
          ctx.between(2, 28),
          'out',
          q,
          r.fullName,
          ctx.pick(const [
            'Sınıf kullanımı için zimmet',
            'Dönem başı malzeme dağıtımı',
            'Branş odası ihtiyacı',
            'Etkinlik hazırlığı',
          ]),
        ),
      );
    }
    if (ctx.rng.nextInt(3) == 0) {
      final q = (ctx.between(3, 12)).toDouble();
      ins += q;
      ops.add(
        _Op(ctx.between(2, 28), 'in', q, '', 'Satın alma sonrası stok girişi'),
      );
    }
    final initial = it.qty + outs - ins;
    ops.sort((a, b) => b.back.compareTo(a.back));

    await ctx.set(itemCol.doc(id), {
      'institutionId': ctx.inst,
      'schoolDocId': ctx.schoolDocId,
      'warehouseId': whIds[w],
      'warehouseName': whNames[w],
      'schoolTypeId': whTypeIds[w],
      'name': it.name,
      'normalizedName': _normalizeTr(it.name),
      'category': it.category,
      'unit': it.unit,
      'quantity': it.qty,
      'minStockLevel': it.min,
      'shelfLocation':
          'Raf ${String.fromCharCode(65 + (i % 6))}-${(i % 4) + 1}',
      'barcode': '869${ctx.between(1000000, 9999999)}${ctx.between(100, 999)}',
      'productLink': '',
      'imageUrl': '',
      'lastUnitPrice': it.price,
      'updatedAt': Timestamp.fromDate(
        _at(_termDay(ctx, ops.isEmpty ? 3 : ops.last.back), 12, 0),
      ),
    });
    ctx.count('Stok kartı');

    var cur = 0.0;
    Future<void> tx(
      String type,
      double q,
      int back,
      int hour,
      String recipient,
      String note,
    ) async {
      final prev = cur;
      cur = type == 'out' ? cur - q : cur + q;
      final day = DateTime(
        ctx.today.year,
        ctx.today.month,
        ctx.today.day - back,
      );
      await ctx.set(txCol.doc(ctx.id('stx_${tn++}')), {
        'institutionId': ctx.inst,
        'warehouseId': whIds[w],
        'warehouseName': whNames[w],
        'schoolTypeId': whTypeIds[w],
        'itemId': id,
        'itemName': it.name,
        'unit': it.unit,
        'type': type,
        'quantity': q,
        'previousQty': prev,
        'newQty': cur,
        'relatedRequestId': '',
        'actorUid': '',
        'actorName': keeper,
        'recipientName': recipient,
        'note': note,
        'createdAt': Timestamp.fromDate(_at(day, hour, 15)),
      });
      ctx.count('Stok hareketi');
    }

    await tx('in', initial, 35, 9, '', 'Dönem başı açılış stoğu');
    var hr = 9;
    for (final op in ops) {
      hr = hr < 16 ? hr + 1 : 9;
      await tx(op.type, op.qty, op.back, hr, op.recipient, op.note);
    }
  }

  // Satın alma / malzeme talepleri
  await _seedRequests(ctx, reqCol, teachers, whIds, whNames, itemIds, itemWh);
}

class _ReqSpec {
  final String itemName;
  final String category;
  final double qty;
  final String unit;
  final String urgency;
  final String status;
  final double price;
  final String description;
  final int itemIdx; // -1 yoksa
  const _ReqSpec(
    this.itemName,
    this.category,
    this.qty,
    this.unit,
    this.urgency,
    this.status,
    this.price,
    this.description, [
    this.itemIdx = -1,
  ]);
}

const List<_ReqSpec> _reqSpecs = [
  _ReqSpec(
    'Tahta Kalemi - Siyah',
    _cOffice,
    10,
    'Kutu',
    'urgent',
    'pending_supervisor',
    120,
    'Stok kritik seviyede, acil gerekli.',
    1,
  ),
  _ReqSpec(
    'Renkli Karton (100 lü)',
    _cOffice,
    12,
    'Paket',
    'normal',
    'pending_supervisor',
    95,
    'Sınıf panoları ve proje çalışmaları için.',
  ),
  _ReqSpec(
    'Akıllı Tahta Kalemi',
    _cIt,
    4,
    'Adet',
    'normal',
    'pending_supervisor',
    180,
    'Eski kalemler çalışmıyor.',
  ),
  _ReqSpec(
    'Yara Bandı',
    _cHealth,
    5,
    'Kutu',
    'normal',
    'approved_for_warehouse',
    30,
    'Revir için ek stok.',
    17,
  ),
  _ReqSpec(
    'Atlama İpi',
    _cSport,
    12,
    'Adet',
    'normal',
    'approved_for_warehouse',
    60,
    'Beden eğitimi dersi için.',
    22,
  ),
  _ReqSpec(
    'Taşınabilir Hoparlör',
    _cIt,
    2,
    'Adet',
    'normal',
    'pending_upper_approver',
    1450,
    'Müzik dersi ve etkinlikler için stokta yok.',
  ),
  _ReqSpec(
    'Projeksiyon Perdesi',
    _cIt,
    1,
    'Adet',
    'normal',
    'pending_upper_approver',
    3200,
    'Konferans salonu perdesi yıpranmış.',
  ),
  _ReqSpec(
    'Fen Laboratuvarı Deney Seti',
    _cLab,
    6,
    'Takım',
    'normal',
    'in_procurement',
    1250,
    'Yeni müfredat deney setleri.',
  ),
  _ReqSpec(
    'Basketbol Potası Filesi',
    _cSport,
    6,
    'Adet',
    'normal',
    'in_procurement',
    85,
    'Pota filelerinin yenilenmesi.',
  ),
  _ReqSpec(
    'Yazıcı Toneri',
    _cIt,
    4,
    'Adet',
    'urgent',
    'quotes_submitted',
    1850,
    'Öğretmenler odası yazıcısı için.',
    6,
  ),
  _ReqSpec(
    'Sınıf Perdesi (Blackout)',
    _cFurn,
    8,
    'Adet',
    'normal',
    'quotes_submitted',
    920,
    'Güneş alan sınıflar için.',
  ),
  _ReqSpec(
    'Ders Kitabı Rafı',
    _cFurn,
    5,
    'Adet',
    'normal',
    'purchase_approved',
    1650,
    'Kütüphane ek raf ihtiyacı.',
  ),
  _ReqSpec(
    'Dijital Termometre',
    _cHealth,
    6,
    'Adet',
    'normal',
    'purchase_ordered',
    160,
    'Revir ve sınıf rehberlik odaları için.',
  ),
  _ReqSpec(
    'Satranç Takımı',
    _cSport,
    10,
    'Takım',
    'normal',
    'purchase_ordered',
    340,
    'Satranç kulübü için.',
  ),
  _ReqSpec(
    'A4 Fotokopi Kağıdı (5\'li Koli)',
    _cOffice,
    20,
    'Koli',
    'normal',
    'delivered',
    285,
    'Dönem başı kağıt ihtiyacı.',
    0,
  ),
  _ReqSpec(
    'Whiteboard Silgisi',
    _cOffice,
    15,
    'Adet',
    'normal',
    'delivered',
    35,
    'Tüm sınıflara dağıtım.',
  ),
  _ReqSpec(
    'Bahçe Hortumu',
    _cRepair,
    2,
    'Adet',
    'normal',
    'delivered',
    420,
    'Bahçe bakımı için.',
  ),
  _ReqSpec(
    'Yangın Tüpü (6 kg)',
    _cRepair,
    3,
    'Adet',
    'urgent',
    'rejected',
    780,
    'Mevcut tüplerin süresi geçmemiş.',
  ),
  _ReqSpec(
    'Masaüstü Bilgisayar',
    _cIt,
    5,
    'Adet',
    'normal',
    'rejected',
    18500,
    'Bütçe dışı olduğu için reddedildi.',
  ),
];

int _stepsFor(String status) {
  switch (status) {
    case 'pending_supervisor':
      return 0;
    case 'approved_for_warehouse':
      return 1;
    case 'pending_upper_approver':
      return 1;
    case 'in_procurement':
      return 2;
    case 'quotes_submitted':
      return 3;
    case 'purchase_approved':
      return 4;
    case 'purchase_ordered':
      return 5;
    case 'delivered':
      return 7;
    case 'rejected':
      return 1;
    default:
      return 0;
  }
}

Map<String, dynamic> _tl(
  String stage,
  String title,
  String actor,
  String note,
  DateTime at,
) => {
  'stage': stage,
  'title': title,
  'actorUid': '',
  'actorName': actor,
  'note': note,
  'timestamp': Timestamp.fromDate(at),
};

Future<void> _seedRequests(
  DemoSeedContext ctx,
  CollectionReference<Map<String, dynamic>> reqCol,
  List<DemoTeacherInfo> teachers,
  List<String> whIds,
  List<String> whNames,
  List<String> itemIds,
  List<int> itemWh,
) async {
  const supervisor = 'Müdür Yardımcısı Kemal Aksoy';
  const upper = 'Okul Müdürü Nermin Özdemir';
  const buyer = 'Satın Alma Birimi';
  const keeper = 'Depo Sorumlusu Hasan Yıldırım';
  var n = 0;
  for (final spec in _reqSpecs) {
    final teacher = ctx.pick(teachers);
    final steps = _stepsFor(spec.status);
    final extraDays = ctx.between(0, 3);
    final base = DateTime(
      ctx.today.year,
      ctx.today.month,
      ctx.today.day - (steps + extraDays + 1),
      9,
      ctx.between(0, 50),
    );
    DateTime t(int step) => base.add(Duration(days: step, hours: step));
    final tl = <Map<String, dynamic>>[
      _tl(
        'created',
        'Malzeme talebi oluşturuldu',
        teacher.fullName,
        spec.description,
        base,
      ),
    ];

    final rejected = spec.status == 'rejected';
    final stockDirect =
        spec.status == 'approved_for_warehouse' ||
        (spec.status == 'delivered' && spec.itemIdx >= 0);
    var supNote = '';
    var upperNote = '';
    var rejection = '';
    var approvedQuoteId = '';
    var orderNote = '';
    var kasaName = '';
    DateTime? receivedAt;
    DateTime? deliveredAt;
    var deliveredBy = '';
    var deliveryNote = '';
    var quotes = <Map<String, dynamic>>[];
    var status = spec.status;

    if (rejected) {
      rejection = spec.description;
      tl.add(_tl('rejected', 'Talep reddedildi', supervisor, rejection, t(1)));
    } else if (spec.status != 'pending_supervisor') {
      if (stockDirect) {
        supNote = 'Depoda mevcut, teslimata yönlendirildi.';
        tl.add(
          _tl(
            'approved_for_warehouse',
            '1. Amir onayladı • Depodan teslimata yönlendirildi',
            supervisor,
            supNote,
            t(1),
          ),
        );
        if (spec.status == 'delivered') {
          deliveredAt = t(2);
          deliveredBy = keeper;
          deliveryNote = 'Zimmetle teslim edildi.';
          tl.add(
            _tl(
              'delivered',
              'Malzeme teslim edildi',
              keeper,
              deliveryNote,
              deliveredAt,
            ),
          );
        }
      } else {
        supNote = 'Depoda yok, üst onaya ve satın almaya yönlendirildi.';
        tl.add(
          _tl(
            'pending_upper_approver',
            '1. Amir onayladı • Stokta yok, üst yetkili oluru bekleniyor',
            supervisor,
            supNote,
            t(1),
          ),
        );
        if (steps >= 2) {
          upperNote = 'Satın alma için uygundur.';
          tl.add(
            _tl(
              'in_procurement',
              'Üst yetkili satın alma oluru verdi • Satın Alma birimine iletildi',
              upper,
              upperNote,
              t(2),
            ),
          );
        }
        if (steps >= 3) {
          final lowest = spec.price * (0.9 + ctx.rng.nextDouble() * 0.05);
          final picks = <String>[];
          while (picks.length < 3) {
            final sName = ctx.pick(_suppliers);
            if (!picks.contains(sName)) picks.add(sName);
          }
          for (var q = 0; q < 3; q++) {
            final unitPrice = double.parse(
              (lowest * (1 + q * 0.07 + ctx.rng.nextDouble() * 0.03))
                  .toStringAsFixed(2),
            );
            quotes.add({
              'id': ctx.id('quote_${n}_$q'),
              'supplierName': picks[q],
              'unitPrice': unitPrice,
              'quantity': spec.qty,
              'vatRate': 20,
              'vatIncluded': true,
              'totalPrice': double.parse(
                (unitPrice * spec.qty).toStringAsFixed(2),
              ),
              'deliveryInfo': '${ctx.between(2, 7)} iş günü içinde teslim',
              'productLink': '',
              'attachmentUrl': '',
              'note': q == 0 ? 'En uygun fiyatlı teklif' : '',
              'isRecommended': q == 0,
              'addedByUid': '',
              'addedByName': buyer,
              'createdAt': Timestamp.fromDate(t(3)),
            });
          }
          tl.add(
            _tl(
              'quotes_submitted',
              '3 adet tedarikçi teklifi üst onaya sunuldu',
              buyer,
              '',
              t(3),
            ),
          );
        }
        if (steps >= 4) {
          approvedQuoteId = quotes.first['id'] as String;
          tl.add(
            _tl(
              'purchase_approved',
              'Teklif onaylandı • ${quotes.first['supplierName']}',
              upper,
              'En uygun teklif seçildi.',
              t(4),
            ),
          );
        }
        if (steps >= 5) {
          orderNote = 'Sipariş verildi, teslimat bekleniyor.';
          kasaName = 'Okul Nakit Kasası';
          tl.add(
            _tl(
              'purchase_ordered',
              'Sipariş verildi • Mal kabul bekleniyor',
              buyer,
              orderNote,
              t(5),
            ),
          );
        }
        if (steps >= 7) {
          receivedAt = t(6);
          tl.add(
            _tl(
              'warehouse_received',
              'Malzeme depoya ulaştı',
              keeper,
              'Mal kabul yapıldı.',
              receivedAt,
            ),
          );
          deliveredAt = t(7);
          deliveredBy = keeper;
          deliveryNote = 'Talep sahibine teslim edildi.';
          tl.add(
            _tl(
              'delivered',
              'Malzeme teslim edildi',
              keeper,
              deliveryNote,
              deliveredAt,
            ),
          );
        }
      }
    }

    final whIdx = spec.itemIdx >= 0 ? itemWh[spec.itemIdx] : 0;
    final updatedAt = tl.isEmpty
        ? base
        : (tl.last['timestamp'] as Timestamp).toDate();

    await ctx.set(reqCol.doc(ctx.id('mreq_${n++}')), {
      'institutionId': ctx.inst,
      'schoolDocId': ctx.schoolDocId,
      'schoolTypeId': teacher.typeId,
      'schoolTypeName': teacher.typeName,
      'requesterUid': teacher.id,
      'requesterName': teacher.fullName,
      'requesterRole': 'teacher',
      'linkedItemId': spec.itemIdx >= 0 ? itemIds[spec.itemIdx] : '',
      'targetWarehouseId': whIds[whIdx],
      'targetWarehouseName': whNames[whIdx],
      'itemName': spec.itemName,
      'normalizedItemName': _normalizeTr(spec.itemName),
      'category': spec.category,
      'quantity': spec.qty,
      'unit': spec.unit,
      'urgency': spec.urgency,
      'productLink': '',
      'imageUrls': <String>[],
      'description': spec.description,
      'status': status,
      'supervisorUid': '',
      'supervisorName': (spec.status == 'pending_supervisor') ? '' : supervisor,
      'supervisorNote': supNote,
      'upperApproverUid': '',
      'upperApproverName': upperNote.isEmpty ? '' : upper,
      'upperApproverNote': upperNote,
      'rejectionReason': rejection,
      'quotes': quotes,
      'approvedQuoteId': approvedQuoteId,
      'selectedKasaId': '',
      'selectedKasaName': kasaName,
      'autoRecordExpense': true,
      'accountingTransactionId': '',
      'orderNote': orderNote,
      'warehouseReceivedAt': receivedAt != null
          ? Timestamp.fromDate(receivedAt)
          : null,
      'warehouseReceivedByName': receivedAt != null ? keeper : '',
      'deliveredAt': deliveredAt != null
          ? Timestamp.fromDate(deliveredAt)
          : null,
      'deliveredByName': deliveredBy,
      'deliveryNote': deliveryNote,
      'timeline': tl,
      'createdAt': Timestamp.fromDate(base),
      'updatedAt': Timestamp.fromDate(updatedAt),
    });
    ctx.count('Satın alma talebi');
  }
}
