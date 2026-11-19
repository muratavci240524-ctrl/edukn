import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// SERVİS İŞLEMLERİ demo verisi.
///
/// Ekran: lib/screens/support_services/transportation/transportation_screen.dart
///  * `schools/{schoolDocId}/vehicles/{id}`: vehicleNumber, plateNumber,
///    driverName, driverPhone, capacity, route, guideName, guidePhone,
///    passengers { studentId: {morning, evening, order} }
///  * `schools/{schoolDocId}/vehicles/{id}/attendance/{yyyy-MM-dd}_{morning|evening}`:
///    date (Timestamp), period, status { studentId: 'came' | 'absent' }
/// Öğrenci dokümanlarına dokunulmaz; atama bilgisi araç dokümanındaki
/// `passengers` haritasındadır.

/// Bu modülün yazdığı üst düzey koleksiyonlar (yok).
const List<String> demoTransportTopCollections = [];

/// `schools/{schoolDocId}/` altında yazılan alt koleksiyonlar.
const List<String> demoTransportSchoolSubcollections = ['vehicles'];

/// Araç altındaki `attendance` alt koleksiyonundaki demo dokümanlarını siler.
Future<int> cleanDemoTransportExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  if (schoolDocId.isEmpty) return 0;
  var deleted = 0;
  final vehicles = await db
      .collection('schools')
      .doc(schoolDocId)
      .collection('vehicles')
      .get();
  for (final v in vehicles.docs) {
    final data = v.data();
    final isOurs =
        v.id.startsWith(prefix) ||
        (data['isDemo'] == true && data['institutionId'] == inst);
    if (!isOurs) continue;
    final att = await v.reference.collection('attendance').get();
    var batch = db.batch();
    var pending = 0;
    for (final d in att.docs) {
      batch.delete(d.reference);
      pending++;
      deleted++;
      if (pending >= 400) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
  }
  return deleted;
}

const List<String> _driverFirst = [
  'Mehmet',
  'Ahmet',
  'Mustafa',
  'Hasan',
  'Ali',
  'İbrahim',
  'Osman',
  'Yusuf',
  'Kemal',
  'Recep',
  'Hüseyin',
  'Cengiz',
];
const List<String> _driverLast = [
  'Yıldırım',
  'Kaya',
  'Demir',
  'Çelik',
  'Şahin',
  'Aydın',
  'Öztürk',
  'Arslan',
  'Doğan',
  'Koç',
  'Kurt',
  'Polat',
];
const List<String> _hostessFirst = [
  'Ayşe',
  'Fatma',
  'Emine',
  'Hatice',
  'Zeynep',
  'Elif',
  'Havva',
  'Sultan',
  'Meryem',
  'Songül',
  'Hülya',
  'Nurcan',
];
const List<String> _hostessLast = [
  'Karaca',
  'Erdoğan',
  'Yalçın',
  'Güneş',
  'Aksoy',
  'Tekin',
  'Bulut',
  'Çakır',
  'Taş',
  'Uçar',
  'Işık',
  'Korkmaz',
];
const List<String> _routeNames = [
  'Merkez - Çarşı Hattı',
  'Yeni Mahalle - Sanayi Hattı',
  'Bahçelievler Hattı',
  'Cumhuriyet - Atatürk Cd. Hattı',
  'Kuzey Sitesi Hattı',
  'Gül Mahallesi Hattı',
  'Fatih - Yıldız Hattı',
  'Hastane - Park Hattı',
  'Çınar Mahallesi Hattı',
  'Üniversite Yolu Hattı',
  'Sahil Hattı',
  'Orman Evleri Hattı',
];
const List<String> _stopNames = [
  'Belediye Önü',
  'Otogar Kavşağı',
  'Park Girişi',
  'Pazar Yeri',
  'Camii Durağı',
  'Hastane Durağı',
  'Lise Kavşağı',
  'Sitesi Kapısı',
  'Fırın Durağı',
  'Postane Önü',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

Future<void> seedDemoTransport(DemoSeedContext ctx) async {
  final vehiclesCol = ctx.schoolCol('vehicles');
  if (vehiclesCol == null) return;
  final students = ctx.allStudents;
  if (students.isEmpty) return;

  final rng = ctx.rng;

  // ~%85 öğrenci servise atanır.
  final shuffled = [...students]..shuffle(rng);
  final assignedCount = math.max(1, (students.length * 0.85).round());
  final assigned = shuffled.take(assignedCount).toList();

  // Araç sayısı ve kapasiteler (toplam kapasite > atanan öğrenci).
  final vCount = (assigned.length / 22).ceil().clamp(3, 12);
  final baseCap = (assigned.length / vCount).ceil();

  final vehicleIds = <String>[];
  final vehicleCaps = <int>[];
  final passengersByVehicle = <Map<String, dynamic>>[];
  final studentsByVehicle = <List<DemoStudentInfo>>[];
  for (var i = 0; i < vCount; i++) {
    vehicleIds.add(ctx.id('veh_${i + 1}'));
    vehicleCaps.add(baseCap + ctx.between(2, 5));
    passengersByVehicle.add(<String, dynamic>{});
    studentsByVehicle.add(<DemoStudentInfo>[]);
  }

  // Öğrencileri sınıfa göre sıralayıp araçlara dağıt (mahalle benzeri kümeleme).
  assigned.sort((a, b) => a.className.compareTo(b.className));
  for (var i = 0; i < assigned.length; i++) {
    var vi = (i * vCount) ~/ assigned.length;
    // Kapasite dolduysa sonraki uygun araca kay.
    var guard = 0;
    while (studentsByVehicle[vi].length >= vehicleCaps[vi] && guard < vCount) {
      vi = (vi + 1) % vCount;
      guard++;
    }
    final s = assigned[i];
    final r = rng.nextInt(10);
    final morning = r != 0; // %10 yalnız akşam
    final evening = r != 1; // %10 yalnız sabah
    final order = studentsByVehicle[vi].length;
    final stopIdx = (order ~/ 3) % _stopNames.length;
    passengersByVehicle[vi][s.id] = {
      'morning': morning,
      'evening': evening,
      'order': order,
      'stopName': _stopNames[stopIdx],
      'stopOrder': stopIdx + 1,
    };
    studentsByVehicle[vi].add(s);
  }

  // Araç dokümanları.
  for (var i = 0; i < vCount; i++) {
    final dFirst = _driverFirst[i % _driverFirst.length];
    final dLast = _driverLast[(i * 5 + 3) % _driverLast.length];
    final hFirst = _hostessFirst[i % _hostessFirst.length];
    final hLast = _hostessLast[(i * 7 + 2) % _hostessLast.length];
    final stopCount = math.min(
      _stopNames.length,
      math.max(3, (studentsByVehicle[i].length / 3).ceil()),
    );
    final stops = <Map<String, dynamic>>[
      for (var k = 0; k < stopCount; k++)
        {
          'order': k + 1,
          'name': _stopNames[k],
          'morningTime': '${_two(7)}:${_two(5 + k * 5)}',
          'eveningTime': '${_two(16)}:${_two(10 + k * 5)}',
        },
    ];
    await ctx.set(vehiclesCol.doc(vehicleIds[i]), {
      'institutionId': ctx.inst,
      'vehicleNumber': '${i + 1}',
      'plateNumber': '34 DEM ${101 + i}',
      'brand': i.isEven ? 'Mercedes Sprinter' : 'Ford Transit',
      'modelYear': 2018 + (i % 6),
      'driverName': '$dFirst $dLast',
      'driverPhone': '0555 100 ${_two(10 + i)} ${_two(20 + i)}',
      'capacity': vehicleCaps[i],
      'route': _routeNames[i % _routeNames.length],
      'stops': stops,
      'guideName': '$hFirst $hLast',
      'guidePhone': '0555 200 ${_two(10 + i)} ${_two(30 + i)}',
      'passengers': passengersByVehicle[i],
      'createdAt': Timestamp.fromDate(ctx.termStart),
    });
    ctx.count('Servis aracı');
  }

  // Son ~10 iş günü (bugün dahil, hafta içi, dönem başlangıcından sonra).
  final days = <DateTime>[];
  var cur = DateTime(ctx.today.year, ctx.today.month, ctx.today.day);
  final start = DateTime(
    ctx.termStart.year,
    ctx.termStart.month,
    ctx.termStart.day,
  );
  var safety = 0;
  while (days.length < 10 && safety < 40) {
    safety++;
    if (cur.weekday <= 5 && !cur.isBefore(start)) days.add(cur);
    cur = cur.subtract(const Duration(days: 1));
  }

  for (var i = 0; i < vCount; i++) {
    final att = vehiclesCol.doc(vehicleIds[i]).collection('attendance');
    final pass = passengersByVehicle[i];
    for (final day in days) {
      final morningAbsent = <String>{};
      for (final period in const ['morning', 'evening']) {
        final status = <String, dynamic>{};
        pass.forEach((sid, v) {
          final p = v as Map<String, dynamic>;
          if (p[period] != true) return;
          bool absent;
          if (period == 'morning') {
            absent = rng.nextInt(100) < 5;
            if (absent) morningAbsent.add(sid);
          } else {
            absent = morningAbsent.contains(sid)
                ? rng.nextInt(100) < 80
                : false;
            if (!absent && rng.nextInt(100) < 2) absent = true;
          }
          status[sid] = absent ? 'absent' : 'came';
        });
        if (status.isEmpty) continue;
        await ctx.set(att.doc('${_dateStr(day)}_$period'), {
          'institutionId': ctx.inst,
          'date': Timestamp.fromDate(day),
          'period': period,
          'status': status,
          'updatedAt': Timestamp.fromDate(
            DateTime(
              day.year,
              day.month,
              day.day,
              period == 'morning' ? 8 : 16,
            ),
          ),
        });
        ctx.count('Servis yoklaması');
      }
    }
  }
}
