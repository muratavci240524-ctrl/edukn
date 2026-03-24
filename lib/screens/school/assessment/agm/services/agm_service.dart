import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../models/agm_assignment_model.dart';
import '../models/agm_assignment_log_model.dart';
import '../models/agm_time_slot_model.dart';
import '../repository/agm_repository.dart';
import 'agm_assignment_engine.dart';

/// AGM iş mantığı katmanı
/// Bu servis, UI ile repository arasında köprü görevi görür.
/// Publish akışı, rollback ve etüt sistemi entegrasyonu buradan yönetilir.
class AgmService {
  final AgmRepository _repo = AgmRepository();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String get _currentUserId => _auth.currentUser?.uid ?? '';
  String get _currentUserName =>
      _auth.currentUser?.displayName ?? 'Bilinmeyen Kullanıcı';

  // ─── CYCLE YÖNETİMİ ───────────────────────────────────────────────────────

  Stream<List<AgmCycle>> watchCycles(
    String institutionId,
    String schoolTypeId,
  ) => _repo.watchCycles(institutionId, schoolTypeId);

  Future<String> createCycle({
    required String institutionId,
    required String schoolTypeId,
    String? title,
    required String referansDenemeSinavId,
    required String referansDenemeSinavAdi,
    List<String> referansDenemeSinavIds = const [],
    List<String> referansDenemeSinavAdlari = const [],
    required DateTime baslangicTarihi,
    required DateTime bitisTarihi,
    int? haftalikMaksimumSaat,
    int? minimumDersSayisi,
    int? minimumGrupOgrenciSayisi,
  }) async {
    final cycle = AgmCycle(
      id: '',
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      title: title,
      referansDenemeSinavId: referansDenemeSinavId,
      referansDenemeSinavAdi: referansDenemeSinavAdi,
      referansDenemeSinavIds: referansDenemeSinavIds,
      referansDenemeSinavAdlari: referansDenemeSinavAdlari,
      baslangicTarihi: baslangicTarihi,
      bitisTarihi: bitisTarihi,
      status: AgmCycleStatus.draft,
      olusturulmaZamani: DateTime.now(),
      olusturanKullaniciId: _currentUserId,
      haftalikMaksimumSaat: haftalikMaksimumSaat,
      minimumDersSayisi: minimumDersSayisi,
      minimumGrupOgrenciSayisi: minimumGrupOgrenciSayisi,
    );
    return await _repo.createCycle(cycle);
  }

  Future<void> updateCycle({
    required String id,
    required String institutionId,
    required String schoolTypeId,
    String? title,
    required String referansDenemeSinavId,
    required String referansDenemeSinavAdi,
    List<String> referansDenemeSinavIds = const [],
    List<String> referansDenemeSinavAdlari = const [],
    required DateTime baslangicTarihi,
    required DateTime bitisTarihi,
    int? haftalikMaksimumSaat,
    int? minimumDersSayisi,
    int? minimumGrupOgrenciSayisi,
    required AgmCycleStatus status,
    required DateTime olusturulmaZamani,
    required String olusturanKullaniciId,
  }) async {
    final cycle = AgmCycle(
      id: id,
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      title: title,
      referansDenemeSinavId: referansDenemeSinavId,
      referansDenemeSinavAdi: referansDenemeSinavAdi,
      referansDenemeSinavIds: referansDenemeSinavIds,
      referansDenemeSinavAdlari: referansDenemeSinavAdlari,
      baslangicTarihi: baslangicTarihi,
      bitisTarihi: bitisTarihi,
      status: status,
      olusturulmaZamani: olusturulmaZamani,
      olusturanKullaniciId: olusturanKullaniciId,
      haftalikMaksimumSaat: haftalikMaksimumSaat,
      minimumDersSayisi: minimumDersSayisi,
      minimumGrupOgrenciSayisi: minimumGrupOgrenciSayisi,
    );
    await _repo.updateCycle(cycle);
  }

  Future<void> lockCycle(String cycleId) async {
    await _repo.updateCycleStatus(cycleId, AgmCycleStatus.locked);
  }

  // ─── GRUP YÖNETİMİ ────────────────────────────────────────────────────────

  Future<void> createGroupsFromTimeSlots({
    required String cycleId,
    required String institutionId,
    required List<AgmTimeSlot> slots,
  }) async {
    for (final slot in slots) {
      for (final entry in slot.ogretmenGirisler) {
        final group = AgmGroup(
          id: '',
          cycleId: cycleId,
          institutionId: institutionId,
          dersId: entry.dersId,
          dersAdi: entry.dersAdi,
          saatDilimiId: slot.id,
          saatDilimiAdi: slot.ad,
          gun: slot.gun,
          baslangicSaat: slot.baslangicSaat,
          bitisSaat: slot.bitisSaat,
          ogretmenId: entry.ogretmenId,
          ogretmenAdi: entry.ogretmenAdi,
          derslikId: entry.derslikId,
          derslikAdi: entry.derslikAdi,
          kapasite: entry.kapasite,
          mevcutOgrenciSayisi: 0,
        );
        await _repo.createGroup(group);
      }
    }
  }

  Stream<List<AgmGroup>> watchGroups(String cycleId) =>
      _repo.watchGroupsByCycle(cycleId);

  // ─── TASLAK OLUŞTURMA ─────────────────────────────────────────────────────

  /// [Grid Screen] Doğrudan StudentNeedProfile listesi alan basit imza.
  /// Gruplar dışarıdan verilir (zaten yüklenmiş).
  Future<AgmDraftResult> generateDraft({
    required AgmCycle cycle,
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<AgmGroup> gruplar,
  }) async {
    final engine = AgmAssignmentEngine(
      cycleId: cycle.id,
      institutionId: cycle.institutionId,
      haftalikMaksimumSaat: cycle.haftalikMaksimumSaat,
    );
    engine.setMinimumDersSayisi(cycle.minimumDersSayisi);
    engine.setMinimumGrupOgrenciSayisi(cycle.minimumGrupOgrenciSayisi);

    final draft = await engine.generateDraft(
      ogrenciProfiller: ogrenciProfiller,
      gruplar: gruplar,
    );

    // Eski atamaları temizle ve yenilerini kaydet
    await _repo.rollbackAssignments(cycle.id);
    await _repo.batchWriteAssignments(draft.atamalar);

    // Grupları güncelle (kazanımlar ve doluluk)
    for (final grup in draft.gruplar) {
      await _repo.updateGroup(grup);
    }

    // Eksik atananları ve yerleşmeyenleri cycle modelinde güncelle
    await _db.collection('agm_cycles').doc(cycle.id).update({
      'unassignedStudentIds': draft.yerlesmeyenOgrenciIds,
      'underAssignedStudentIds': draft.eksikAtananOgrenciIds,
      'unassignedReasons': draft.yerlesmemeNedenleri,
    });

    return draft;
  }

  /// [Legacy / Servis katmanı] Sınav sonuç haritası alan overload.
  Future<AgmDraftResult> generateDraftFromResults({
    required String cycleId,
    required String institutionId,
    required int? haftalikMaksimumSaat,
    required Map<String, Map<String, double>> examResultsByStudent,
    required Map<String, String> ogrenciAdlari,
    required Map<String, String> ogrenciSubeleri,
    required Map<String, String> subeAdlari,
  }) async {
    final cycleDoc = await _db.collection('agm_cycles').doc(cycleId).get();
    if (!cycleDoc.exists) throw Exception('Cycle bulunamadı');
    final cycle = AgmCycle.fromMap(cycleDoc.data()!, cycleDoc.id);

    final gruplar = await _repo.getGroupsByCycle(cycleId);
    final profiller = examResultsByStudent.entries.map((entry) {
      final ogrenciId = entry.key;
      final basarilar = entry.value;
      final ihtiyaclar = basarilar.map((k, v) => MapEntry(k, 1.0 - v));
      final subeId = ogrenciSubeleri[ogrenciId] ?? '';
      return StudentNeedProfile(
        ogrenciId: ogrenciId,
        ogrenciAdi: ogrenciAdlari[ogrenciId] ?? ogrenciId,
        subeId: subeId,
        subeAdi: subeAdlari[subeId] ?? subeId,
        dersIhtiyaclari: ihtiyaclar,
      );
    }).toList();

    final engine = AgmAssignmentEngine(
      cycleId: cycleId,
      institutionId: institutionId,
      haftalikMaksimumSaat: haftalikMaksimumSaat,
    );
    engine.setMinimumDersSayisi(cycle.minimumDersSayisi);
    engine.setMinimumGrupOgrenciSayisi(cycle.minimumGrupOgrenciSayisi);

    final draft = await engine.generateDraft(
      ogrenciProfiller: profiller,
      gruplar: gruplar,
    );

    await _repo.rollbackAssignments(cycleId);
    await _repo.batchWriteAssignments(draft.atamalar);

    // Eksik atananları ve yerleşmeyenleri cycle modelinde güncelle
    await _db.collection('agm_cycles').doc(cycleId).update({
      'unassignedStudentIds': draft.yerlesmeyenOgrenciIds,
      'underAssignedStudentIds': draft.eksikAtananOgrenciIds,
      'absentStudentIds': cycle.absentStudentIds, // Değişmedi
      'unassignedReasons': draft.yerlesmemeNedenleri,
    });

    return draft;
  }

  // ─── MANUEL OVERRIDE ──────────────────────────────────────────────────────

  /// Öğrenciyi başka gruba taşır + log kaydeder.
  /// [assignmentId] boş ise yeni atama oluşturulur (sınava girmeyenler senaryosu).
  Future<void> moveStudent({
    required String assignmentId,
    required String cycleId,
    required String ogrenciId,
    required String ogrenciAdi,
    required String eskiGrupId,
    required String eskiGrupAdi,
    required String yeniGrupId,
    required String yeniGrupAdi,
    required bool isOverride,
    String? subeId,
    String? subeAdi,
    String? overrideNedeni,
  }) async {
    // 0) Cycle bilgilerini al (min ders sayısı ve instId için)
    final cycleDoc = await _db.collection('agm_cycles').doc(cycleId).get();
    if (!cycleDoc.exists) return;
    final cycle = AgmCycle.fromMap(cycleDoc.data()!, cycleDoc.id);

    if (assignmentId.isEmpty) {
      // Yeni atama oluştur (sınava girmeyen öğrenci manuel atama)
      final yeniAtama = AgmAssignment(
        id: '',
        cycleId: cycleId,
        institutionId: cycle.institutionId,
        groupId: yeniGrupId,
        ogrenciId: ogrenciId,
        ogrenciAdi: ogrenciAdi,
        subeId: subeId ?? '',
        subeAdi: subeAdi ?? '',
        ihtiyacSkoru: 0.0,
        atamaTipi: AgmAssignmentType.manual,
        olusturulmaZamani: DateTime.now(),
      );
      await _repo.batchWriteAssignments([yeniAtama]);
    } else {
      await _repo.moveAssignment(assignmentId, yeniGrupId, yeniGrupAdi);
      if (eskiGrupId.isNotEmpty) {
        await _repo.updateGroupStudentCount(eskiGrupId, -1);
      }
    }
    await _repo.updateGroupStudentCount(yeniGrupId, 1);

    // 1) Döngü listelerini güncelle
    final currentAssignments = await _repo.getAssignmentsByStudent(
      cycleId,
      ogrenciId,
    );
    final count = currentAssignments.length;

    final isUnder =
        cycle.minimumDersSayisi != null && count < cycle.minimumDersSayisi!;

    await _repo.updateCycleStudentLists(
      cycleId,
      unassignedRemove: [ogrenciId],
      absentRemove: [ogrenciId],
      underAssignedAdd: isUnder ? [ogrenciId] : null,
      underAssignedRemove: !isUnder ? [ogrenciId] : null,
    );

    // Log
    await _repo.addLog(
      AgmAssignmentLog(
        id: '',
        cycleId: cycleId,
        institutionId: '',
        ogrenciId: ogrenciId,
        ogrenciAdi: ogrenciAdi,
        eskiGrupId: eskiGrupId,
        eskiGrupAdi: eskiGrupAdi,
        yeniGrupId: yeniGrupId,
        yeniGrupAdi: yeniGrupAdi,
        yapanKullaniciId: _currentUserId,
        yapanKullaniciAdi: _currentUserName,
        isOverride: isOverride,
        overrideNedeni: overrideNedeni,
        tarih: DateTime.now(),
      ),
    );
  }

  /// Doğrudan yeni atama yapar (sınava girmeyen veya kategori bazlı manuel atama)
  Future<void> manualAssign({
    required String cycleId,
    required String ogrenciId,
    required String ogrenciAdi,
    required String subeId,
    required String subeAdi,
    required String yeniGrupId,
    required String yeniGrupAdi,
    required bool isAbsent,
  }) async {
    final cycleDoc = await _db.collection('agm_cycles').doc(cycleId).get();
    if (!cycleDoc.exists) return;
    final cycle = AgmCycle.fromMap(cycleDoc.data()!, cycleDoc.id);

    final yeniAtama = AgmAssignment(
      id: '',
      cycleId: cycleId,
      institutionId: cycle.institutionId,
      groupId: yeniGrupId,
      ogrenciId: ogrenciId,
      ogrenciAdi: ogrenciAdi,
      subeId: subeId,
      subeAdi: subeAdi,
      groupName: yeniGrupAdi,
      ihtiyacSkoru: 0.0,
      atamaTipi: AgmAssignmentType.manual,
      olusturulmaZamani: DateTime.now(),
    );

    await _repo.batchWriteAssignments([yeniAtama]);
    await _repo.updateGroupStudentCount(yeniGrupId, 1);

    // Listeleri güncelle
    await _repo.updateCycleStudentLists(
      cycleId,
      unassignedRemove: [ogrenciId],
      absentRemove: isAbsent ? [ogrenciId] : null,
    );

    // Log
    await _repo.addLog(
      AgmAssignmentLog(
        id: '',
        cycleId: cycleId,
        institutionId: cycle.institutionId,
        ogrenciId: ogrenciId,
        ogrenciAdi: ogrenciAdi,
        eskiGrupId: '',
        eskiGrupAdi: isAbsent ? 'Sınava Girmeyenler' : 'Yerleşmeyenler',
        yeniGrupId: yeniGrupId,
        yeniGrupAdi: yeniGrupAdi,
        yapanKullaniciId: _currentUserId,
        yapanKullaniciAdi: _currentUserName,
        isOverride: false,
        tarih: DateTime.now(),
      ),
    );
  }

  // ─── PUBLISH AKIŞI ────────────────────────────────────────────────────────

  /// Cycle'ı yayınlar ve mevcut etüt sistemine atamaları yazar.
  ///
  /// Publish adımları:
  ///   1. Cycle status = published
  ///   2. Atamaları etut_requests koleksiyonuna yaz
  ///   3. Bildirimleri tetikle (notificationRequests)
  Future<void> publishCycle({
    required AgmCycle cycle,
    required List<AgmGroup> gruplar,
    required List<AgmAssignment> atamalar,
  }) async {
    final batch = _db.batch();

    // 1) Cycle status güncelle
    batch.update(_db.collection('agm_cycles').doc(cycle.id), {
      'status': AgmCycleStatus.published.name,
    });

    // Haftanın başı (Pazartesi)
    final cycleStartOfWeek = cycle.baslangicTarihi.subtract(
      Duration(days: cycle.baslangicTarihi.weekday - 1),
    );
    final cycleStartTs = Timestamp.fromDate(
      DateTime(
        cycleStartOfWeek.year,
        cycleStartOfWeek.month,
        cycleStartOfWeek.day,
      ),
    );

    // Haftanın sonu (Pazar)
    final cycleEndOfWeek = cycleStartOfWeek.add(const Duration(days: 6));
    final cycleEndTs = Timestamp.fromDate(
      DateTime(
        cycleEndOfWeek.year,
        cycleEndOfWeek.month,
        cycleEndOfWeek.day,
        23,
        59,
        59,
      ),
    );

    // Gün isimlerinden index'e çevrim (Pazartesi = 1, Pazar = 7)
    int dayNameToIndex(String dayName) {
      final d = dayName
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('İ', 'i')
          .trim();
      switch (d) {
        case 'pazartesi':
          return 1;
        case 'sali':
          return 2;
        case 'carsamba':
          return 3;
        case 'persembe':
          return 4;
        case 'cuma':
          return 5;
        case 'cumartesi':
          return 6;
        case 'pazar':
          return 7;
        default:
          return 1;
      }
    }

    // 2) Etüt sistemine yaz
    // Atamaları grup bazında topla (her grup 1 etüt olacak, öğrencileri listeye eklenecek)
    final Map<String, List<AgmAssignment>> assignmentsByGroup = {};
    for (final atama in atamalar) {
      assignmentsByGroup.putIfAbsent(atama.groupId, () => []).add(atama);
    }

    for (final entry in assignmentsByGroup.entries) {
      final groupId = entry.key;
      final groupAssignments = entry.value;

      final grup = gruplar.firstWhere(
        (g) => g.id == groupId,
        orElse: () => gruplar.first,
      );

      final etutRef = _db.collection('etut_requests').doc();

      // Tam tarihi hesapla
      final dayIndex = dayNameToIndex(grup.gun);
      final exactDate = cycleStartOfWeek.add(Duration(days: dayIndex - 1));

      // Start/End time hesapla
      final startParts = grup.baslangicSaat.split(':');
      final endParts = grup.bitisSaat.split(':');
      DateTime? startTime;
      DateTime? endTime;

      if (startParts.length == 2 && endParts.length == 2) {
        startTime = DateTime(
          exactDate.year,
          exactDate.month,
          exactDate.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        );
        endTime = DateTime(
          exactDate.year,
          exactDate.month,
          exactDate.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        );
      }

      batch.set(etutRef, {
        'id': etutRef.id,
        'institutionId': cycle.institutionId,
        'studentId': groupAssignments.first.ogrenciId, // Legacy uyumluluk
        'studentIds': groupAssignments.map((a) => a.ogrenciId).toList(),
        'teacherId': grup.ogretmenId,
        'teacherName': grup.ogretmenAdi,
        'dersId': grup.dersId,
        'dersAdi': grup.dersAdi,
        'lessonName': grup.dersAdi,
        'gun': grup.gun,
        'baslangicSaat': grup.baslangicSaat,
        'bitisSaat': grup.bitisSaat,
        'agmCycleId': cycle.id,
        'agmGroupId': grup.id,
        'date': Timestamp.fromDate(exactDate),
        'startTime': startTime != null ? Timestamp.fromDate(startTime) : null,
        'endTime': endTime != null ? Timestamp.fromDate(endTime) : null,
        'className': 'AGM - ${grup.saatDilimiAdi}', // Opsiyonel, gösterim için
        'weekStart': cycleStartTs,
        'weekEnd': cycleEndTs,
        'status': 'active',
        'type': 'Etut',
        'isGroup': groupAssignments.length > 1,
        'groupStudentCount': groupAssignments.length,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _currentUserId,
      });

      // 3) Bildirim tetikle (her öğrenci için)
      for (final atama in groupAssignments) {
        final notifRef = _db.collection('notificationRequests').doc();
        batch.set(notifRef, {
          'type': 'agm_assignment',
          'recipientId': atama.ogrenciId,
          'title': 'Yeni Etüt Programı',
          'body':
              '${grup.dersAdi} etüdünüz ${grup.gun} ${grup.baslangicSaat}-${grup.bitisSaat} olarak oluşturuldu.',
          'institutionId': cycle.institutionId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
    await batch.commit();
  }

  /// Cycle'ı yayından kaldırır: bağlı etütleri (ve gerekirse bildirimleri) siler,
  /// cycle durumunu tekrar active yapar.
  Future<void> unpublishCycle(String cycleId) async {
    final batch = _db.batch();

    // 1) İlgili etütleri bul ve sil
    final etutsQuery = await _db
        .collection('etut_requests')
        .where('agmCycleId', isEqualTo: cycleId)
        .get();

    for (final doc in etutsQuery.docs) {
      batch.delete(doc.reference);
    }

    // 2) Cycle status güncelle
    batch.update(_db.collection('agm_cycles').doc(cycleId), {
      'status': AgmCycleStatus.locked.name,
    });

    await batch.commit();
  }

  // ─── RAPORLAR ─────────────────────────────────────────────────────────────

  Future<List<AgmAssignmentLog>> getLogs(String cycleId) =>
      _repo.getLogsByCycle(cycleId);

  Future<List<AgmAssignment>> getAssignmentsByCycle(String cycleId) =>
      _repo.getAssignmentsByCycle(cycleId);
}
