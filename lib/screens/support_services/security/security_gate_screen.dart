import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/school/student_movement_model.dart';
import '../../../services/pdf_service.dart';
import '../../../services/student_movement_service.dart';
import '../../../services/user_permission_service.dart';
import '../../../widgets/edukn_app_bar.dart';

/// Okul Misafir / Ziyaretçi Giriş-Çıkış Kaydı Modeli
/// Koleksiyon Yolu: `schools/{schoolDocId}/visitorLogs/{id}`
class SchoolVisitorRecord {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String dateStr; // 'YYYY-MM-DD'
  final String status; // 'inside' | 'exited'

  final String visitorName;
  final String visitorCategory;
  final String visitorPhone;
  final String identityCheckInfo; // Örn: 'Kimlik Görüldü • ****1234'
  final String badgeNo; // Örn: 'Z-04'
  final String vehiclePlate;
  final String companyOrRelation;

  final String targetUnit;
  final String hostStaffUid;
  final String hostStaffName;
  final String visitReason;
  final String entryNote;
  final String exitNote;

  final DateTime entryTime;
  final DateTime? exitTime;
  final String checkedInByUid;
  final String checkedInByName;
  final String checkedOutByUid;
  final String checkedOutByName;

  const SchoolVisitorRecord({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    required this.dateStr,
    required this.status,
    required this.visitorName,
    required this.visitorCategory,
    this.visitorPhone = '',
    this.identityCheckInfo = '',
    this.badgeNo = '',
    this.vehiclePlate = '',
    this.companyOrRelation = '',
    required this.targetUnit,
    this.hostStaffUid = '',
    this.hostStaffName = '',
    required this.visitReason,
    this.entryNote = '',
    this.exitNote = '',
    required this.entryTime,
    this.exitTime,
    this.checkedInByUid = '',
    this.checkedInByName = '',
    this.checkedOutByUid = '',
    this.checkedOutByName = '',
  });

  bool get isInside => status == 'inside';

  int get stayMinutes {
    final end = exitTime ?? DateTime.now();
    final diff = end.difference(entryTime).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  String get stayDurationLabel {
    final m = stayMinutes;
    if (m < 60) return '$m dk';
    final h = m ~/ 60;
    final rem = m % 60;
    return rem == 0 ? '$h sa' : '$h sa $rem dk';
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'dateStr': dateStr,
      'status': status,
      'visitorName': visitorName,
      'visitorCategory': visitorCategory,
      'visitorPhone': visitorPhone,
      'identityCheckInfo': identityCheckInfo,
      'badgeNo': badgeNo,
      'vehiclePlate': vehiclePlate,
      'companyOrRelation': companyOrRelation,
      'targetUnit': targetUnit,
      'hostStaffUid': hostStaffUid,
      'hostStaffName': hostStaffName,
      'visitReason': visitReason,
      'entryNote': entryNote,
      'exitNote': exitNote,
      'entryTime': Timestamp.fromDate(entryTime),
      'exitTime': exitTime != null ? Timestamp.fromDate(exitTime!) : null,
      'checkedInByUid': checkedInByUid,
      'checkedInByName': checkedInByName,
      'checkedOutByUid': checkedOutByUid,
      'checkedOutByName': checkedOutByName,
    };
  }

  factory SchoolVisitorRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime parseDt(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw) ?? fallback;
      return fallback;
    }

    return SchoolVisitorRecord(
      id: doc.id,
      institutionId: (d['institutionId'] ?? '').toString(),
      schoolDocId: (d['schoolDocId'] ?? '').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (d['schoolTypeName'] ?? '').toString(),
      dateStr: (d['dateStr'] ?? '').toString(),
      status: (d['status'] ?? 'inside').toString(),
      visitorName: (d['visitorName'] ?? '').toString(),
      visitorCategory: (d['visitorCategory'] ?? 'Misafir / Ziyaretçi')
          .toString(),
      visitorPhone: (d['visitorPhone'] ?? '').toString(),
      identityCheckInfo: (d['identityCheckInfo'] ?? '').toString(),
      badgeNo: (d['badgeNo'] ?? '').toString(),
      vehiclePlate: (d['vehiclePlate'] ?? '').toString(),
      companyOrRelation: (d['companyOrRelation'] ?? '').toString(),
      targetUnit: (d['targetUnit'] ?? '').toString(),
      hostStaffUid: (d['hostStaffUid'] ?? '').toString(),
      hostStaffName: (d['hostStaffName'] ?? '').toString(),
      visitReason: (d['visitReason'] ?? '').toString(),
      entryNote: (d['entryNote'] ?? '').toString(),
      exitNote: (d['exitNote'] ?? '').toString(),
      entryTime: parseDt(d['entryTime'], DateTime.now()),
      exitTime: d['exitTime'] != null
          ? parseDt(d['exitTime'], DateTime.now())
          : null,
      checkedInByUid: (d['checkedInByUid'] ?? '').toString(),
      checkedInByName: (d['checkedInByName'] ?? '').toString(),
      checkedOutByUid: (d['checkedOutByUid'] ?? '').toString(),
      checkedOutByName: (d['checkedOutByName'] ?? '').toString(),
    );
  }
}

/// Destek Hizmetleri → Güvenlik Kapı (Öğrenci Çıkış Onayı & Misafir Giriş-Çıkış Yönetimi)
class SecurityGateScreen extends StatefulWidget {
  final int initialTabIndex; // 0: Öğrenci Çıkış Onayı, 1: Misafir Giriş-Çıkış
  final String? fixedInstitutionId;
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final bool isStandalonePortal;

  const SecurityGateScreen({
    super.key,
    this.initialTabIndex = 0,
    this.fixedInstitutionId,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.isStandalonePortal = false,
  });

  @override
  State<SecurityGateScreen> createState() => _SecurityGateScreenState();
}

class _SecurityGateScreenState extends State<SecurityGateScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StudentMovementService _movementService = StudentMovementService();

  int _activeTab = 0;
  bool _loading = true;
  bool _submitting = false;

  String _institutionId = '';
  String _schoolDocId = '';
  String _schoolName = 'Okul Müdürlüğü';
  String _securityActorUid = '';
  String _securityActorName = 'Güvenlik Görevlisi';

  Timer? _clockTicker;

  // Kurum personeli ve okul türleri (Misafir geldiğinde ilgili Okul Türü kapsamında bildirim gönderebilmek için)
  List<
    ({String uid, String name, String roleLabel, List<String> schoolTypeIds})
  >
  _staffOptions = [];
  List<({String id, String name})> _schoolTypes = [];
  String _selectedVisitorSchoolTypeId = '';

  // Sekme 0: Öğrenci Çıkış Onayı filtreleri
  final TextEditingController _studentGateSearchCtrl = TextEditingController();
  String _studentGateSearch = '';

  // Sekme 1: Misafir Giriş-Çıkış durumu ve form alanları
  DateTime _visitorLogDate = DateTime.now();
  final TextEditingController _visitorSearchCtrl = TextEditingController();
  String _visitorSearch = '';

  String _visitorCategory = 'Öğrenci Velisi / Yakını';
  String _targetUnit = 'Okul İdaresi (Müdür / Müdür Yardımcısı)';
  String _selectedHostUid = '';

  final TextEditingController _visitorNameCtrl = TextEditingController();
  final TextEditingController _visitorPhoneCtrl = TextEditingController();
  final TextEditingController _identityInfoCtrl = TextEditingController(
    text: 'Kimlik Kontrolü Yapıldı',
  );
  final TextEditingController _badgeNoCtrl = TextEditingController();
  final TextEditingController _vehiclePlateCtrl = TextEditingController();
  final TextEditingController _companyOrRelCtrl = TextEditingController();
  final TextEditingController _hostCustomNameCtrl = TextEditingController();
  final TextEditingController _visitReasonCtrl = TextEditingController(
    text: 'Veli Görüşmesi / Öğrenci Durum Bilgisi',
  );
  final TextEditingController _entryNoteCtrl = TextEditingController();

  static const List<String> _visitorCategories = [
    'Öğrenci Velisi / Yakını',
    'Kayıt / Tanıtım Görüşmesi (Aday Veli)',
    'Resmi Kurum Görevlisi / Denetmen',
    'Kargo / Tedarikçi / Teknik Servis',
    'Mezun / Misafir / Diğer Ziyaretçi',
  ];

  static const List<String> _unitOptions = [
    'Okul İdaresi (Müdür / Müdür Yardımcısı)',
    'Rehberlik / PDR Servisi',
    'Muhasebe / Öğrenci İşleri / Kayıt Kabul',
    'Öğretmen Görüşmesi',
    'Destek Hizmetleri / Teknik Birim / Depo',
  ];

  static const List<String> _reasonTemplates = [
    'Veli Görüşmesi / Öğrenci Durum Bilgisi',
    'Yeni Kayıt / Okul Tanıtım Görüşmesi',
    'Evrak / Resmi Belge Teslimi',
    'Kargo / Malzeme Teslimatı / Teknik Bakım',
    'Randevulu Kurum / İdare Ziyareti',
  ];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTabIndex.clamp(0, 1);
    _bootstrap();
    _clockTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    _studentGateSearchCtrl.dispose();
    _visitorSearchCtrl.dispose();
    _visitorNameCtrl.dispose();
    _visitorPhoneCtrl.dispose();
    _identityInfoCtrl.dispose();
    _badgeNoCtrl.dispose();
    _vehiclePlateCtrl.dispose();
    _companyOrRelCtrl.dispose();
    _hostCustomNameCtrl.dispose();
    _visitReasonCtrl.dispose();
    _entryNoteCtrl.dispose();
    super.dispose();
  }

  static String _normTr(String s) {
    return s
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

  Future<void> _bootstrap() async {
    try {
      String? instId = widget.fixedInstitutionId?.trim();
      if (instId == null || instId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        final userData = await UserPermissionService.loadUserData();
        instId = userData?['institutionId']?.toString().trim();
        if (instId == null || instId.isEmpty) {
          final email = user?.email ?? '';
          if (email.isNotEmpty) {
            instId = await UserPermissionService.resolveInstitutionId(email);
          }
        }
      }

      final actor = await _movementService.resolveCurrentActor();
      final resolvedInst = (instId ?? '').trim();
      String schoolDocId = '';
      String schoolName = (widget.fixedSchoolTypeName ?? '').trim().isNotEmpty
          ? widget.fixedSchoolTypeName!.trim()
          : 'Okul Müdürlüğü';

      if (resolvedInst.isNotEmpty) {
        schoolDocId = await _movementService.resolveSchoolDocId(resolvedInst);
        try {
          final sDoc = await _db.collection('schools').doc(schoolDocId).get();
          if (sDoc.exists) {
            final sd = sDoc.data() ?? {};
            final raw = (sd['schoolName'] ?? sd['name'] ?? '')
                .toString()
                .trim();
            if (raw.isNotEmpty) {
              final unitName = (widget.fixedSchoolTypeName ?? '').trim();
              schoolName =
                  unitName.isNotEmpty &&
                      !raw.toLowerCase().contains(unitName.toLowerCase())
                  ? '$raw • $unitName'
                  : raw;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      final fixedStId = (widget.fixedSchoolTypeId ?? '').trim();
      setState(() {
        _institutionId = resolvedInst;
        _schoolDocId = schoolDocId;
        _schoolName = schoolName;
        _securityActorUid = actor.uid;
        _securityActorName = actor.name.isNotEmpty
            ? actor.name
            : 'Güvenlik Görevlisi';
        if (fixedStId.isNotEmpty) {
          _selectedVisitorSchoolTypeId = fixedStId;
        }
        _loading = false;
      });

      if (resolvedInst.isNotEmpty) {
        _loadStaffOptions(resolvedInst);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStaffOptions(String instId) async {
    try {
      final variants = {
        instId.trim(),
        instId.trim().toUpperCase(),
        instId.trim().toLowerCase(),
      }.where((e) => e.isNotEmpty).toList();

      final results = await Future.wait([
        _db
            .collection('users')
            .where('institutionId', whereIn: variants)
            .get()
            .timeout(const Duration(seconds: 6)),
        _db
            .collection('schoolTypes')
            .where('institutionId', whereIn: variants)
            .get()
            .timeout(const Duration(seconds: 6)),
      ]);

      final snap = results[0];
      final stSnap = results[1];

      final loadedTypes = <({String id, String name})>[];
      for (final stDoc in stSnap.docs) {
        final stData = stDoc.data();
        if (stData['isActive'] == false) continue;
        final stName =
            (stData['schoolTypeName'] ?? stData['name'] ?? stData['type'] ?? '')
                .toString()
                .trim();
        if (stName.isNotEmpty) {
          loadedTypes.add((id: stDoc.id, name: stName));
        }
      }
      loadedTypes.sort((a, b) => a.name.compareTo(b.name));

      final fixedStId = (widget.fixedSchoolTypeId ?? '').trim();
      final list =
          <
            ({
              String uid,
              String name,
              String roleLabel,
              List<String> schoolTypeIds,
            })
          >[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isActive'] == false) continue;
        final role = (data['role'] ?? data['userType'] ?? '')
            .toString()
            .toLowerCase();
        if (role == 'student' ||
            role == 'ogrenci' ||
            role == 'parent' ||
            role == 'veli') {
          continue;
        }
        final stIds = <String>[];
        if (data['schoolTypes'] is Iterable) {
          for (final item in (data['schoolTypes'] as Iterable)) {
            final s = item.toString().trim();
            if (s.isNotEmpty) stIds.add(s);
          }
        }
        final singleSt = (data['schoolTypeId'] ?? '').toString().trim();
        if (singleSt.isNotEmpty && !stIds.contains(singleSt)) {
          stIds.add(singleSt);
        }

        // Eğer ekran belirli bir Okul Türü içerisinden açıldıysa, başka okul türlerinin personelini karıştırma
        if (fixedStId.isNotEmpty &&
            stIds.isNotEmpty &&
            !stIds.contains(fixedStId)) {
          continue;
        }

        final full =
            (data['fullName'] ??
                    '${data['name'] ?? ''} ${data['surname'] ?? ''}')
                .toString()
                .trim();
        if (full.isEmpty) continue;
        String roleTr = 'Personel';
        if (role.contains('mudur_yardimcisi')) {
          roleTr = 'Müdür Yrd.';
        } else if (role.contains('mudur') || role.contains('manager')) {
          roleTr = 'Okul Müdürü';
        } else if (role.contains('rehber')) {
          roleTr = 'Rehberlik / PDR';
        } else if (role.contains('ogretmen') || role.contains('teacher')) {
          roleTr = 'Öğretmen';
        } else if (role.contains('muhasebe')) {
          roleTr = 'Muhasebe';
        }
        list.add((
          uid: d.id,
          name: full,
          roleLabel: roleTr,
          schoolTypeIds: stIds,
        ));
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) {
        setState(() {
          _staffOptions = list;
          _schoolTypes = loadedTypes;
          if (_selectedVisitorSchoolTypeId.isEmpty && loadedTypes.isNotEmpty) {
            _selectedVisitorSchoolTypeId = loadedTypes.first.id;
          }
        });
      }
    } catch (_) {}
  }

  Stream<List<SchoolVisitorRecord>> _watchVisitorsForDate(String dateStr) {
    if (_schoolDocId.isEmpty) return Stream.value(const []);
    final fixedStId = (widget.fixedSchoolTypeId ?? '').trim();
    return _db
        .collection('schools')
        .doc(_schoolDocId)
        .collection('visitorLogs')
        .where('dateStr', isEqualTo: dateStr)
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map(SchoolVisitorRecord.fromDoc)
              .where(
                (r) =>
                    fixedStId.isEmpty ||
                    r.schoolTypeId.isEmpty ||
                    r.schoolTypeId == fixedStId,
              )
              .toList();
          items.sort((a, b) => b.entryTime.compareTo(a.entryTime));
          return items;
        });
  }

  Stream<List<SchoolVisitorRecord>> _watchActiveInsideVisitors() {
    if (_schoolDocId.isEmpty) return Stream.value(const []);
    final fixedStId = (widget.fixedSchoolTypeId ?? '').trim();
    return _db
        .collection('schools')
        .doc(_schoolDocId)
        .collection('visitorLogs')
        .where('status', isEqualTo: 'inside')
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map(SchoolVisitorRecord.fromDoc)
              .where(
                (r) =>
                    fixedStId.isEmpty ||
                    r.schoolTypeId.isEmpty ||
                    r.schoolTypeId == fixedStId,
              )
              .toList();
          items.sort((a, b) => b.entryTime.compareTo(a.entryTime));
          return items;
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AKSİYONLAR: ÖĞRENCİ ÇIKIŞ ONAYI & MİSAFİR GİRİŞ / ÇIKIŞ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _confirmStudentGateExitDialog(
    StudentMovementRecord record,
  ) async {
    final gateNoteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF059669),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Güvenlik Öğrenci Çıkış Onayı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.studentName} (${record.className}) öğrencisinin kapıdan çıkış yaptığını onaylıyor musunuz?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Text(
                  'Çıkış Türü: ${record.exitMode}\n'
                  '${record.receiverName.isNotEmpty ? "Teslim Alacak: ${record.receiverName} (${record.receiverRelation})\n" : ""}'
                  'Onaylandığında öğrenci kalan derslerde OTOMATİK İZİNLİ yazılır ve idare/veli bilgilendirilir.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0C4A6E),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildPremiumTextField(
                controller: gateNoteCtrl,
                label: 'Güvenlik Kapı Notu',
                badgeText: 'İsteğe Bağlı',
                hint: 'Örn: Kimlik kontrolü yapıldı, velisine teslim edildi',
                icon: Icons.shield_outlined,
                accentColor: const Color(0xFF059669),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Çıkışı Onayla'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      final excused = await _movementService.approveGateExit(
        record: record,
        gateNote: gateNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '✓ ${record.studentName} kapı çıkışı onaylandı'
            '${excused.isNotEmpty ? " (${excused.map((h) => "$h.").join(",")} dersler otomatik izinli işlendi)" : ""}.',
          ),
        ),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVisitorCheckIn() async {
    final name = _visitorNameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Lütfen giriş yapan misafirin adını ve soyadını yazınız.');
      return;
    }
    if (_visitReasonCtrl.text.trim().isEmpty) {
      _showError('Lütfen ziyaret sebebini seçiniz veya yazınız.');
      return;
    }
    if (_schoolDocId.isEmpty) {
      _showError('Okul kaydı çözümlenemedi.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      final dateStr = StudentMovementService.formatDateYmd(now);

      String resolvedHostName = _hostCustomNameCtrl.text.trim();
      String resolvedSchoolTypeId = (widget.fixedSchoolTypeId ?? '').trim();
      if (resolvedSchoolTypeId.isEmpty) {
        resolvedSchoolTypeId = _selectedVisitorSchoolTypeId.trim();
      }
      if (_selectedHostUid.isNotEmpty) {
        final match = _staffOptions.where((s) => s.uid == _selectedHostUid);
        if (match.isNotEmpty) {
          resolvedHostName = match.first.name;
          if (resolvedSchoolTypeId.isEmpty &&
              match.first.schoolTypeIds.isNotEmpty) {
            resolvedSchoolTypeId = match.first.schoolTypeIds.first;
          }
        }
      }
      if (resolvedSchoolTypeId.isEmpty && _schoolTypes.isNotEmpty) {
        resolvedSchoolTypeId = _schoolTypes.first.id;
      }

      String resolvedSchoolTypeName = (widget.fixedSchoolTypeName ?? '').trim();
      if (resolvedSchoolTypeName.isEmpty && resolvedSchoolTypeId.isNotEmpty) {
        for (final st in _schoolTypes) {
          if (st.id == resolvedSchoolTypeId) {
            resolvedSchoolTypeName = st.name;
            break;
          }
        }
      }

      final docRef = _db
          .collection('schools')
          .doc(_schoolDocId)
          .collection('visitorLogs')
          .doc();

      final rec = SchoolVisitorRecord(
        id: docRef.id,
        institutionId: _institutionId,
        schoolDocId: _schoolDocId,
        schoolTypeId: resolvedSchoolTypeId,
        schoolTypeName: resolvedSchoolTypeName,
        dateStr: dateStr,
        status: 'inside',
        visitorName: name,
        visitorCategory: _visitorCategory,
        visitorPhone: _visitorPhoneCtrl.text.trim(),
        identityCheckInfo: _identityInfoCtrl.text.trim(),
        badgeNo: _badgeNoCtrl.text.trim(),
        vehiclePlate: _vehiclePlateCtrl.text.trim().toUpperCase(),
        companyOrRelation: _companyOrRelCtrl.text.trim(),
        targetUnit: _targetUnit,
        hostStaffUid: _selectedHostUid,
        hostStaffName: resolvedHostName,
        visitReason: _visitReasonCtrl.text.trim(),
        entryNote: _entryNoteCtrl.text.trim(),
        entryTime: now,
        checkedInByUid: _securityActorUid,
        checkedInByName: _securityActorName,
      );

      await docRef.set(rec.toMap());

      // Uygulama Ayarlarındaki "Ziyaretçi Giriş Bildirimi" tercihine göre ilgili Okul Türü alıcılarına ilet
      final timeStr = DateFormat('HH:mm').format(now);
      await _movementService.notifyVisitorEvent(
        institutionId: _institutionId,
        schoolDocId: _schoolDocId,
        schoolTypeId: resolvedSchoolTypeId,
        isExit: false,
        visitorLogId: docRef.id,
        visitorName: name,
        visitorCategory: _visitorCategory,
        targetUnit: _targetUnit,
        visitReason: rec.visitReason,
        hostStaffUid: _selectedHostUid,
        badgeNo: rec.badgeNo,
        timeStr: timeStr,
      );

      _visitorNameCtrl.clear();
      _visitorPhoneCtrl.clear();
      _badgeNoCtrl.clear();
      _vehiclePlateCtrl.clear();
      _companyOrRelCtrl.clear();
      _hostCustomNameCtrl.clear();
      _entryNoteCtrl.clear();
      setState(() {
        _selectedHostUid = '';
        _visitorLogDate = DateTime.now();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '✓ Misafir girişi kaydedildi: $name (Saat $timeStr)'
            '${resolvedHostName.isNotEmpty ? " • $resolvedHostName bilgilendirildi" : ""}.',
          ),
        ),
      );
    } catch (e) {
      _showError('Misafir girişi kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmVisitorCheckOutDialog(SchoolVisitorRecord v) async {
    final exitNoteCtrl = TextEditingController(
      text: v.badgeNo.isNotEmpty
          ? '${v.badgeNo} nolu ziyaretçi kartı teslim alındı'
          : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFF0D9488),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Misafir Çıkış Kaydı Onayı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${v.visitorName} isimli ziyaretçinin okuldan çıkış yaptığını onaylıyor musunuz?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: Text(
                  'Giriş Saati: ${DateFormat("HH:mm").format(v.entryTime)} • İçeride Kalma Süresi: ${v.stayDurationLabel}\n'
                  'Görüşülen Birim: ${v.targetUnit}${v.hostStaffName.isNotEmpty ? " (${v.hostStaffName})" : ""}'
                  '${v.badgeNo.isNotEmpty ? "\nLütfen '${v.badgeNo}' numaralı ziyaretçi kartını teslim almayı unutmayınız." : ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF115E59),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildPremiumTextField(
                controller: exitNoteCtrl,
                label: 'Çıkış / Kart Teslim Notu',
                badgeText: 'İsteğe Bağlı',
                hint: 'Örn: Ziyaretçi kartı teslim alındı, çıkış yapıldı',
                icon: Icons.assignment_turned_in_outlined,
                accentColor: const Color(0xFF0D9488),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Misafir Çıkışını Kaydet'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      await _db
          .collection('schools')
          .doc(_schoolDocId)
          .collection('visitorLogs')
          .doc(v.id)
          .update({
            'status': 'exited',
            'exitTime': Timestamp.fromDate(now),
            'exitNote': exitNoteCtrl.text.trim(),
            'checkedOutByUid': _securityActorUid,
            'checkedOutByName': _securityActorName,
          });

      // Uygulama Ayarlarındaki "Ziyaretçi Çıkış Bildirimi" tercihine göre ilgili Okul Türü alıcılarına ilet
      final exitTimeStr = DateFormat('HH:mm').format(now);
      await _movementService.notifyVisitorEvent(
        institutionId: _institutionId,
        schoolDocId: _schoolDocId,
        schoolTypeId: v.schoolTypeId.isNotEmpty
            ? v.schoolTypeId
            : _selectedVisitorSchoolTypeId,
        isExit: true,
        visitorLogId: v.id,
        visitorName: v.visitorName,
        visitorCategory: v.visitorCategory,
        targetUnit: v.targetUnit,
        visitReason: v.visitReason,
        hostStaffUid: v.hostStaffUid,
        badgeNo: v.badgeNo,
        timeStr: exitTimeStr,
        stayDurationLabel: v.stayDurationLabel,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0D9488),
          content: Text(
            '✓ ${v.visitorName} çıkışı kaydedildi (Çıkış: $exitTimeStr).',
          ),
        ),
      );
    } catch (e) {
      _showError('Çıkış kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _printVisitorLogPdf(List<SchoolVisitorRecord> records) async {
    if (records.isEmpty) {
      _showError('Seçili tarihte yazdırılacak ziyaretçi kaydı bulunmuyor.');
      return;
    }
    try {
      final bytes = await _generateVisitorLogPdfBytes(
        records: records.reversed.toList(),
        date: _visitorLogDate,
        schoolName: _schoolName,
      );
      final dStr = StudentMovementService.formatDateYmd(_visitorLogDate);
      await Printing.layoutPdf(
        name: 'Ziyaretci_Giris_Cikis_Defteri_$dStr.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      _showError('PDF oluşturulamadı: $e');
    }
  }

  static Future<Uint8List> _generateVisitorLogPdfBytes({
    required List<SchoolVisitorRecord> records,
    required DateTime date,
    required String schoolName,
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts[0], bold: fonts[1]),
    );

    final dateFmt = DateFormat('dd.MM.yyyy').format(date);
    final dayName = StudentMovementService.dayNameTr(date.weekday);
    final navy = PdfColor.fromHex('#0F172A');
    final border = PdfColor.fromHex('#CBD5E1');
    final headerBg = PdfColor.fromHex('#F1F5F9');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    schoolName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'OKUL GÜVENLİK KAPISI — GÜNLÜK MİSAFİR / ZİYARETÇİ GİRİŞ-ÇIKIŞ KAYIT DEFTERİ',
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#0284C7'),
                    ),
                  ),
                ],
              ),
              pw.Text(
                'Tarih: $dateFmt ($dayName)\nToplam Ziyaretçi: ${records.length}',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: navy,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: border, width: 0.6),
            headerDecoration: pw.BoxDecoration(color: headerBg),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
            headers: const [
              '#',
              'Adı Soyadı',
              'Kategori / Yakınlık',
              'Telefon & Plaka',
              'Kart / Kimlik',
              'Görüşülen Birim / Kişi',
              'Ziyaret Sebebi',
              'Giriş',
              'Çıkış',
              'Süre',
              'Güvenlik Görevlisi',
            ],
            data: List.generate(records.length, (i) {
              final r = records[i];
              final phonePlate = [
                if (r.visitorPhone.isNotEmpty) r.visitorPhone,
                if (r.vehiclePlate.isNotEmpty) r.vehiclePlate,
              ].join(' / ');
              final badgeId = [
                if (r.badgeNo.isNotEmpty) 'Kart: ${r.badgeNo}',
                if (r.identityCheckInfo.isNotEmpty) r.identityCheckInfo,
              ].join('\n');
              final unitHost = [
                r.targetUnit,
                if (r.hostStaffName.isNotEmpty) r.hostStaffName,
              ].join(' • ');
              return [
                '${i + 1}',
                r.visitorName,
                r.companyOrRelation.isNotEmpty
                    ? '${r.visitorCategory}\n(${r.companyOrRelation})'
                    : r.visitorCategory,
                phonePlate.isEmpty ? '-' : phonePlate,
                badgeId.isEmpty ? '-' : badgeId,
                unitHost,
                r.visitReason,
                DateFormat('HH:mm').format(r.entryTime),
                r.exitTime != null
                    ? DateFormat('HH:mm').format(r.exitTime!)
                    : 'İçeride',
                r.stayDurationLabel,
                r.checkedInByName,
              ];
            }),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Kapı Güvenlik Görevlisi',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text('İmza', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Nöbetçi Müdür Yardımcısı / İdare',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Kontrol / İmza',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFFDC2626), content: Text(msg)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANA EKRAN & ÜST GÜVENLİK MOD ÇUBUĞU (SADECE 2 SEKME)
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final standalone =
          widget.isStandalonePortal || !Navigator.of(context).canPop();
      return Scaffold(
        backgroundColor: const Color(0xFFF3F6FC),
        appBar: EduknAppBar(
          title: 'Güvenlik Kapı & Misafir Yönetimi',
          showBackButton: !standalone,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_institutionId.isEmpty || _schoolDocId.isEmpty) {
      final standalone =
          widget.isStandalonePortal || !Navigator.of(context).canPop();
      return Scaffold(
        backgroundColor: const Color(0xFFF3F6FC),
        appBar: EduknAppBar(
          title: 'Güvenlik Kapı & Misafir Yönetimi',
          showBackButton: !standalone,
          actions: standalone ? _buildStandaloneActions() : null,
        ),
        body: const Center(child: Text('Kurum bilgisi çözümlenemedi.')),
      );
    }

    final standalone =
        widget.isStandalonePortal || !Navigator.of(context).canPop();
    final todayStr = StudentMovementService.formatDateYmd(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: EduknAppBar(
        title: 'Güvenlik Kapı & Misafir Giriş-Çıkış',
        subtitle: _schoolName,
        showBackButton: !standalone,
        actions: standalone ? _buildStandaloneActions() : null,
      ),
      body: StreamBuilder<List<StudentMovementRecord>>(
        stream: _movementService.watchMovementsForDate(
          schoolDocId: _schoolDocId,
          dateStr: todayStr,
          schoolTypeId: widget.fixedSchoolTypeId ?? '',
        ),
        builder: (context, studentSnap) {
          final studentMovements =
              studentSnap.data ?? const <StudentMovementRecord>[];
          final pendingStudentExits = studentMovements
              .where(
                (r) =>
                    r.status == StudentMovementStatus.pendingGate ||
                    r.status == StudentMovementStatus.parentArrived ||
                    r.status == StudentMovementStatus.earlyPickupNotified,
              )
              .toList();

          return StreamBuilder<List<SchoolVisitorRecord>>(
            stream: _watchActiveInsideVisitors(),
            builder: (context, activeVisitorsSnap) {
              final insideVisitors =
                  activeVisitorsSnap.data ?? const <SchoolVisitorRecord>[];

              return Column(
                children: [
                  _buildSecurityTopBar(
                    pendingStudentCount: pendingStudentExits.length,
                    insideVisitorCount: insideVisitors.length,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        _buildStudentExitApprovalTab(studentMovements),
                        _buildVisitorManagementTab(insideVisitors),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSecurityTopBar({
    required int pendingStudentCount,
    required int insideVisitorCount,
  }) {
    final now = DateTime.now();
    final liveClock =
        '${DateFormat("dd.MM.yyyy").format(now)} ${StudentMovementService.dayNameTr(now.weekday)} • ${DateFormat("HH:mm").format(now)}';

    final tabs = [
      (
        idx: 0,
        title: 'ÖĞRENCİ ÇIKIŞ ONAYI',
        icon: Icons.sensor_door_rounded,
        color: const Color(0xFF0284C7),
        badge: pendingStudentCount,
      ),
      (
        idx: 1,
        title: 'MİSAFİR GİRİŞ - ÇIKIŞ',
        icon: Icons.badge_rounded,
        color: const Color(0xFF0D9488),
        badge: insideVisitorCount,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactMobile = constraints.maxWidth < 680;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompactMobile ? 10 : 18,
            vertical: isCompactMobile ? 8 : 11,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tabs.map((t) {
                      final sel = _activeTab == t.idx;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: isCompactMobile ? 7 : 10,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _activeTab = t.idx),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompactMobile ? 12 : 16,
                              vertical: isCompactMobile ? 8.5 : 10,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? t.color
                                  : t.color.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? t.color
                                    : t.color.withValues(alpha: 0.25),
                              ),
                              boxShadow: sel
                                  ? [
                                      BoxShadow(
                                        color: t.color.withValues(alpha: 0.24),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  t.icon,
                                  size: isCompactMobile ? 16 : 18,
                                  color: sel ? Colors.white : t.color,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  t.title,
                                  style: GoogleFonts.inter(
                                    fontSize: isCompactMobile ? 11.8 : 12.6,
                                    fontWeight: FontWeight.w800,
                                    color: sel ? Colors.white : t.color,
                                  ),
                                ),
                                if (t.badge > 0) ...[
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sel ? Colors.white : t.color,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${t.badge}',
                                      style: TextStyle(
                                        fontSize: 10.6,
                                        fontWeight: FontWeight.w900,
                                        color: sel ? t.color : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (!isCompactMobile) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_filled_rounded,
                        size: 15,
                        color: Color(0xFF0F172A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        liveClock,
                        style: GoogleFonts.inter(
                          fontSize: 11.6,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 0: SADECE ÖĞRENCİ ÇIKIŞ ONAYI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentExitApprovalTab(
    List<StudentMovementRecord> todayRecords,
  ) {
    const accent = Color(0xFF0284C7);
    final q = _normTr(_studentGateSearch);
    bool matches(StudentMovementRecord r) {
      if (q.isEmpty) return true;
      final hay = _normTr(
        '${r.studentName} ${r.className} ${r.studentNo} ${r.receiverName} ${r.vehiclePlate}',
      );
      return hay.contains(q);
    }

    final pendingList = todayRecords
        .where(
          (r) =>
              (r.status == StudentMovementStatus.pendingGate ||
                  r.status == StudentMovementStatus.parentArrived ||
                  r.status == StudentMovementStatus.earlyPickupNotified) &&
              matches(r),
        )
        .toList();

    final approvedList = todayRecords
        .where(
          (r) => r.status == StudentMovementStatus.exitedSchool && matches(r),
        )
        .toList();

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final outerPad = isMobile ? 12.0 : 18.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: EdgeInsets.fromLTRB(outerPad, outerPad, outerPad, 36),
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 14 : 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Öğrenci Kapı Çıkış Kontrolü',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildCounterChip(
                            label: 'Bekleyen Çıkış: ${pendingList.length}',
                            bg: pendingList.isNotEmpty
                                ? const Color(0xFFFFF7ED)
                                : const Color(0xFFF0F9FF),
                            fg: pendingList.isNotEmpty
                                ? const Color(0xFFEA580C)
                                : const Color(0xFF0369A1),
                            border: pendingList.isNotEmpty
                                ? const Color(0xFFFB923C)
                                : const Color(0xFFBAE6FD),
                          ),
                          _buildCounterChip(
                            label: 'Bugün Çıkan: ${approvedList.length}',
                            bg: const Color(0xFFECFDF5),
                            fg: const Color(0xFF059669),
                            border: const Color(0xFFA7F3D0),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPremiumTextField(
                    controller: _studentGateSearchCtrl,
                    label: 'Öğrenci / Veli / Plaka Hızlı Arama',
                    hint:
                        'Öğrenci adı, numarası, şubesi veya veli adı yazın...',
                    icon: Icons.search_rounded,
                    accentColor: accent,
                    onChanged: (v) => setState(() => _studentGateSearch = v),
                    suffix: _studentGateSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _studentGateSearchCtrl.clear();
                              setState(() => _studentGateSearch = '');
                            },
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bekleyen Çıkışlar
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: pendingList.isNotEmpty
                    ? const Color(0xFFFFF7ED)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: pendingList.isNotEmpty
                      ? const Color(0xFFFB923C)
                      : const Color(0xFFE2E8F0),
                  width: pendingList.isNotEmpty ? 1.4 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sensor_door_rounded,
                        color: pendingList.isNotEmpty
                            ? const Color(0xFFEA580C)
                            : accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Çıkış Onayı Bekleyen Öğrenciler (${pendingList.length})',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pendingList.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 26,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 34,
                            color: Colors.blueGrey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Şu an kapı çıkış onayı bekleyen öğrenci bulunmuyor.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'İdare tarafından öğrenciye çıkış izni verildiğinde anlık olarak bu ekrana düşer.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...pendingList.map(_buildStudentPendingGateCard),
                ],
              ),
            ),

            if (approvedList.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bugün Kapıdan Çıkışı Onaylanan Öğrenciler (${approvedList.length})',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...approvedList.map(_buildStudentApprovedGateTile),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentPendingGateCard(StudentMovementRecord r) {
    final issueTime = DateFormat('HH:mm').format(r.createdAt);
    final isEarly = r.type == StudentMovementType.earlyPickup;
    final badgeColor = isEarly
        ? const Color(0xFF0D9488)
        : const Color(0xFF0284C7);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
          width: 1.3,
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${r.studentName} • Şube: ${r.className}${r.studentNo.isNotEmpty ? " (No: ${r.studentNo})" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isEarly ? 'Veli Erken Alma' : r.exitMode,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'İzin Saati: $issueTime${r.plannedExitTime.isNotEmpty ? " • Planlanan: ${r.plannedExitTime}" : ""}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (r.receiverName.isNotEmpty || r.vehiclePlate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '👤 Teslim Alacak: ${r.receiverName.isNotEmpty ? r.receiverName : "Veli"}'
                      '${r.receiverRelation.isNotEmpty ? " (${r.receiverRelation})" : ""}'
                      '${r.receiverPhone.isNotEmpty ? " • Tel: ${r.receiverPhone}" : ""}'
                      '${r.vehiclePlate.isNotEmpty ? " • Plaka: ${r.vehiclePlate}" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 12.4,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                Text(
                  '📋 Ders: ${r.lessonHour}. Ders${r.lessonTimeRangeLabel.isNotEmpty ? " (${r.lessonTimeRangeLabel})" : ""}'
                  '${r.reason.isNotEmpty ? " • Neden: ${r.reason}" : ""}'
                  '${r.notes.isNotEmpty ? " • Not: ${r.notes}" : ""}'
                  ' • Onaylayan İdare: ${r.createdByName}',
                  style: GoogleFonts.inter(
                    fontSize: 11.6,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, btnConstraints) {
              final approveBtn = ElevatedButton.icon(
                onPressed: _submitting
                    ? null
                    : () => _confirmStudentGateExitDialog(r),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.verified_user_rounded, size: 19),
                label: Text(
                  'ÇIKIŞ ONAYI VER',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                  ),
                ),
              );
              return MediaQuery.sizeOf(context).width < 560
                  ? SizedBox(width: double.infinity, child: approveBtn)
                  : approveBtn;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStudentApprovedGateTile(StudentMovementRecord r) {
    final exitTime = r.gateApprovedAt != null
        ? DateFormat('HH:mm').format(r.gateApprovedAt!)
        : DateFormat('HH:mm').format(r.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              children: [
                Text(
                  exitTime,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                    color: const Color(0xFF059669),
                  ),
                ),
                Text(
                  'ÇIKTI',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.studentName} • Şube: ${r.className}${r.studentNo.isNotEmpty ? " (No: ${r.studentNo})" : ""}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.2,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.exitMode}'
                  '${r.receiverName.isNotEmpty ? " • Teslim Alan: ${r.receiverName}" : ""}'
                  '${r.gateApprovedByName.isNotEmpty ? " • Güvenlik Onayı: ${r.gateApprovedByName}" : ""}'
                  '${r.gateNote.isNotEmpty ? " • Kapı Notu: ${r.gateNote}" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 1: MİSAFİR / ZİYARETÇİ GİRİŞ - ÇIKIŞ YÖNETİMİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVisitorManagementTab(List<SchoolVisitorRecord> insideVisitors) {
    const accent = Color(0xFF0D9488);
    final selectedDateStr = StudentMovementService.formatDateYmd(
      _visitorLogDate,
    );
    final now = DateTime.now();
    final liveEntryStr =
        '${DateFormat("dd.MM.yyyy").format(now)} ${StudentMovementService.dayNameTr(now.weekday)} • Giriş Saati: ${DateFormat("HH:mm").format(now)}';

    final q = _normTr(_visitorSearch);
    bool matchesVisitor(SchoolVisitorRecord v) {
      if (q.isEmpty) return true;
      final hay = _normTr(
        '${v.visitorName} ${v.visitorCategory} ${v.vehiclePlate} ${v.badgeNo} ${v.targetUnit} ${v.hostStaffName} ${v.companyOrRelation}',
      );
      return hay.contains(q);
    }

    final filteredInside = insideVisitors.where(matchesVisitor).toList();

    return StreamBuilder<List<SchoolVisitorRecord>>(
      stream: _watchVisitorsForDate(selectedDateStr),
      builder: (context, dateSnap) {
        final dayRecords = (dateSnap.data ?? const <SchoolVisitorRecord>[])
            .where(matchesVisitor)
            .toList();

        final isMobile = MediaQuery.sizeOf(context).width < 600;
        final outerPad = isMobile ? 12.0 : 18.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: EdgeInsets.fromLTRB(outerPad, outerPad, outerPad, 36),
              children: [
                // 1. ŞU AN OKUL İÇİNDE OLAN MİSAFİRLER (ÇIKIŞ TAKİBİ)
                Container(
                  padding: EdgeInsets.all(isMobile ? 14 : 18),
                  decoration: BoxDecoration(
                    color: filteredInside.isNotEmpty
                        ? const Color(0xFFF0FDFA)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: filteredInside.isNotEmpty
                          ? const Color(0xFF2DD4BF)
                          : const Color(0xFFE2E8F0),
                      width: filteredInside.isNotEmpty ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.how_to_reg_rounded,
                                color: accent,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Şu An Okulda Olan Aktif Misafirler (${filteredInside.length})',
                                  style: GoogleFonts.inter(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _buildCounterChip(
                            label:
                                'İçerideki Ziyaretçi: ${insideVisitors.length}',
                            bg: Colors.white,
                            fg: accent,
                            border: accent.withValues(alpha: 0.35),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (filteredInside.isEmpty)
                        Text(
                          'Şu an okul içinde aktif misafir/ziyaretçi bulunmuyor. Yeni gelen ziyaretçiyi aşağıdaki formdan kaydedebilirsiniz.',
                          style: GoogleFonts.inter(
                            fontSize: 12.2,
                            color: const Color(0xFF64748B),
                          ),
                        )
                      else
                        ...filteredInside.map(_buildActiveVisitorCard),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. YENİ MİSAFİR GİRİŞ KAYDI OLUŞTURMA KARTI
                Container(
                  padding: EdgeInsets.all(isMobile ? 14 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: accent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Yeni Misafir / Ziyaretçi Giriş Kaydı',
                                      style: GoogleFonts.inter(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      'Kimlik ve ziyaretçi kartı bilgisini işleyip ilgili birime yönlendirin',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              '🕒 $liveEntryStr',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ),

                      // Ziyaretçi Kategorisi (Alt Alta Çeklist)
                      _buildVerticalSingleChecklist(
                        label: 'Ziyaretçi Kategorisi',
                        accentColor: accent,
                        selectedValue: _visitorCategory,
                        options: _visitorCategories,
                        onSelected: (v) => setState(() => _visitorCategory = v),
                      ),
                      const SizedBox(height: 16),

                      // Misafir Kimlik, İletişim, Kart ve Plaka Alanları
                      LayoutBuilder(
                        builder: (context, c) {
                          final wide = c.maxWidth > 680;
                          final nameF = _buildPremiumTextField(
                            controller: _visitorNameCtrl,
                            label: 'Misafir Adı Soyadı',
                            badgeText: 'Zorunlu',
                            hint: 'Örn: Mehmet Kaya',
                            icon: Icons.person_outline_rounded,
                            accentColor: accent,
                          );
                          final phoneF = _buildPremiumTextField(
                            controller: _visitorPhoneCtrl,
                            label: 'Telefon Numarası',
                            hint: '05XX XXX XX XX',
                            icon: Icons.phone_outlined,
                            accentColor: accent,
                          );
                          final relF = _buildPremiumTextField(
                            controller: _companyOrRelCtrl,
                            label: 'Kurum / Firma / Öğrenci Yakınlığı',
                            hint: 'Örn: 603 Velisi, İlçe MEM, Aras Kargo...',
                            icon: Icons.business_outlined,
                            accentColor: accent,
                          );
                          final idF = _buildPremiumTextField(
                            controller: _identityInfoCtrl,
                            label: 'Kimlik Doğrulama Notu',
                            hint: 'Kimlik Kontrolü Yapıldı / ****1234',
                            icon: Icons.credit_card_rounded,
                            accentColor: accent,
                          );
                          final badgeF = _buildPremiumTextField(
                            controller: _badgeNoCtrl,
                            label: 'Verilen Ziyaretçi Kart No',
                            hint: 'Örn: Z-01, Misafir-4',
                            icon: Icons.badge_outlined,
                            accentColor: accent,
                          );
                          final plateF = _buildPremiumTextField(
                            controller: _vehiclePlateCtrl,
                            label: 'Araç Plakası (Varsa)',
                            hint: 'Örn: 06 ABC 123',
                            icon: Icons.directions_car_outlined,
                            accentColor: accent,
                          );

                          if (wide) {
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(flex: 2, child: nameF),
                                    const SizedBox(width: 12),
                                    Expanded(child: phoneF),
                                    const SizedBox(width: 12),
                                    Expanded(flex: 2, child: relF),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(flex: 2, child: idF),
                                    const SizedBox(width: 12),
                                    Expanded(child: badgeF),
                                    const SizedBox(width: 12),
                                    Expanded(child: plateF),
                                  ],
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              nameF,
                              const SizedBox(height: 12),
                              phoneF,
                              const SizedBox(height: 12),
                              relF,
                              const SizedBox(height: 12),
                              idF,
                              const SizedBox(height: 12),
                              badgeF,
                              const SizedBox(height: 12),
                              plateF,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Ziyaret Edilecek Birim (Alt Alta Çeklist)
                      _buildVerticalSingleChecklist(
                        label: 'Ziyaret Edilecek Birim / Bölüm',
                        accentColor: accent,
                        selectedValue: _targetUnit,
                        options: _unitOptions,
                        onSelected: (v) => setState(() => _targetUnit = v),
                      ),
                      const SizedBox(height: 14),

                      // İlgili Okul Türü / Kademe Seçimi (Genel kapı ekranından açıldıysa)
                      if ((widget.fixedSchoolTypeId ?? '').trim().isEmpty &&
                          _schoolTypes.isNotEmpty) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ziyaret Edilen Okul Türü / Kademe (Bildirim Bu Okul Türüne İletilir)',
                              style: GoogleFonts.inter(
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            InputDecorator(
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                prefixIcon: const Icon(
                                  Icons.school_outlined,
                                  size: 19,
                                  color: accent,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value:
                                      _schoolTypes.any(
                                        (t) =>
                                            t.id ==
                                            _selectedVisitorSchoolTypeId,
                                      )
                                      ? _selectedVisitorSchoolTypeId
                                      : _schoolTypes.first.id,
                                  isExpanded: true,
                                  items: _schoolTypes
                                      .map(
                                        (t) => DropdownMenuItem(
                                          value: t.id,
                                          child: Text(t.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(
                                        () => _selectedVisitorSchoolTypeId = v,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Görüşülecek Personel Seçimi (Bildirim Gider)
                      LayoutBuilder(
                        builder: (context, c) {
                          final wide = c.maxWidth > 680;
                          final visibleStaff = _staffOptions.where((s) {
                            if (_selectedVisitorSchoolTypeId.isEmpty ||
                                s.schoolTypeIds.isEmpty) {
                              return true;
                            }
                            return s.schoolTypeIds.contains(
                              _selectedVisitorSchoolTypeId,
                            );
                          }).toList();
                          final staffDropdown = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Görüşülecek Personel Seçimi (Seçilirse Anlık Bildirim Gider)',
                                style: GoogleFonts.inter(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              InputDecorator(
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  prefixIcon: const Icon(
                                    Icons.notifications_active_outlined,
                                    size: 19,
                                    color: accent,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value:
                                        visibleStaff.any(
                                          (s) => s.uid == _selectedHostUid,
                                        )
                                        ? _selectedHostUid
                                        : '',
                                    isExpanded: true,
                                    items: [
                                      const DropdownMenuItem(
                                        value: '',
                                        child: Text(
                                          'Genel Birim Ziyareti (Kişi Seçilmedi)',
                                        ),
                                      ),
                                      ...visibleStaff.map(
                                        (s) => DropdownMenuItem(
                                          value: s.uid,
                                          child: Text(
                                            '${s.name} (${s.roleLabel})',
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      final next = v ?? '';
                                      setState(() {
                                        _selectedHostUid = next;
                                        if (next.isNotEmpty) {
                                          final m = visibleStaff.firstWhere(
                                            (s) => s.uid == next,
                                          );
                                          _hostCustomNameCtrl.text = m.name;
                                          if ((widget.fixedSchoolTypeId ?? '')
                                                  .trim()
                                                  .isEmpty &&
                                              m.schoolTypeIds.length == 1) {
                                            _selectedVisitorSchoolTypeId =
                                                m.schoolTypeIds.first;
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );

                          final customHostField = _buildPremiumTextField(
                            controller: _hostCustomNameCtrl,
                            label: 'Görüşülecek Kişi Adı (Manuel / Ek Bilgi)',
                            badgeText: 'İsteğe Bağlı',
                            hint: 'Örn: Nöbetçi Müdür Yardımcısı',
                            icon: Icons.person_pin_outlined,
                            accentColor: accent,
                          );

                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: staffDropdown),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: customHostField),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              staffDropdown,
                              const SizedBox(height: 12),
                              customHostField,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Hızlı Ziyaret Sebebi Şablonları (Alt Alta Çeklist)
                      _buildVerticalSingleChecklist(
                        label: 'Hızlı Ziyaret Sebebi Seçimi',
                        accentColor: accent,
                        selectedValue: _visitReasonCtrl.text.trim(),
                        options: _reasonTemplates,
                        onSelected: (v) =>
                            setState(() => _visitReasonCtrl.text = v),
                      ),
                      const SizedBox(height: 12),
                      _buildPremiumTextField(
                        controller: _visitReasonCtrl,
                        label: 'Ziyaret Sebebi / Açıklama',
                        badgeText: 'Zorunlu',
                        hint: 'Ziyaret konusunu yazınız...',
                        icon: Icons.description_outlined,
                        accentColor: accent,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _buildPremiumTextField(
                        controller: _entryNoteCtrl,
                        label: 'Güvenlik Giriş Notu',
                        badgeText: 'İsteğe Bağlı',
                        hint:
                            'Örn: Kargo kolisi danışmaya bırakıldı / Refakatçi ile çıktı...',
                        icon: Icons.shield_outlined,
                        accentColor: accent,
                      ),
                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submitVisitorCheckIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 20),
                          label: Text(
                            'MİSAFİR GİRİŞİNİ KAYDET VE İÇERİ AL',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 3. GÜNLÜK MİSAFİR GİRİŞ-ÇIKIŞ DEFTERİ & PDF DÖKÜMÜ
                Container(
                  padding: EdgeInsets.all(isMobile ? 14 : 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.menu_book_rounded,
                                color: Color(0xFF0F172A),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Günlük Misafir Giriş-Çıkış Defteri (${dayRecords.length} Kayıt)',
                                  style: GoogleFonts.inter(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _visitorLogDate,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 1),
                                    ),
                                  );
                                  if (picked != null) {
                                    setState(() => _visitorLogDate = picked);
                                  }
                                },
                                icon: const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 15,
                                ),
                                label: Text(
                                  DateFormat(
                                    'dd.MM.yyyy',
                                  ).format(_visitorLogDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: dayRecords.isEmpty
                                    ? null
                                    : () => _printVisitorLogPdf(dayRecords),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.print_rounded, size: 16),
                                label: const Text(
                                  'Ziyaretçi Defteri PDF Yazdır',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildPremiumTextField(
                        controller: _visitorSearchCtrl,
                        label: 'Ziyaretçi Kayıtlarında Ara',
                        hint:
                            'Misafir adı, plaka, kart no, görüşülen birim veya kişi ara...',
                        icon: Icons.search_rounded,
                        accentColor: accent,
                        onChanged: (v) => setState(() => _visitorSearch = v),
                        suffix: _visitorSearch.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _visitorSearchCtrl.clear();
                                  setState(() => _visitorSearch = '');
                                },
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      if (dayRecords.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Seçilen tarihte kayıtlı misafir giriş-çıkışı bulunmuyor.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        )
                      else
                        ...dayRecords.map(_buildVisitorHistoryTile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveVisitorCard(SchoolVisitorRecord v) {
    final inTime = DateFormat('HH:mm').format(v.entryTime);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0D9488).withValues(alpha: 0.35),
          width: 1.3,
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 690),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      v.visitorName,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    _buildCounterChip(
                      label: v.visitorCategory,
                      bg: const Color(0xFFF0FDFA),
                      fg: const Color(0xFF0D9488),
                      border: const Color(0xFF99F6E4),
                    ),
                    if (v.badgeNo.isNotEmpty)
                      _buildCounterChip(
                        label: 'Kart: ${v.badgeNo}',
                        bg: const Color(0xFFFEF3C7),
                        fg: const Color(0xFFB45309),
                        border: const Color(0xFFFDE68A),
                      ),
                    if (v.vehiclePlate.isNotEmpty)
                      _buildCounterChip(
                        label: '🚗 ${v.vehiclePlate}',
                        bg: const Color(0xFFF1F5F9),
                        fg: const Color(0xFF0F172A),
                        border: const Color(0xFFCBD5E1),
                      ),
                    _buildCounterChip(
                      label: 'Giriş: $inTime • ${v.stayDurationLabel}',
                      bg: const Color(0xFF0D9488),
                      fg: Colors.white,
                      border: const Color(0xFF0D9488),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '📍 Birim: ${v.targetUnit}${v.hostStaffName.isNotEmpty ? " • Görüşülen: ${v.hostStaffName}" : ""}'
                  '${v.companyOrRelation.isNotEmpty ? " • Yakınlık/Firma: ${v.companyOrRelation}" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sebep: ${v.visitReason}'
                  '${v.visitorPhone.isNotEmpty ? " • Tel: ${v.visitorPhone}" : ""}'
                  '${v.identityCheckInfo.isNotEmpty ? " • ${v.identityCheckInfo}" : ""}'
                  '${v.entryNote.isNotEmpty ? " • Not: ${v.entryNote}" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final checkoutBtn = ElevatedButton.icon(
                onPressed: _submitting
                    ? null
                    : () => _confirmVisitorCheckOutDialog(v),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  'ÇIKIŞ YAPTI',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.6,
                  ),
                ),
              );
              return MediaQuery.sizeOf(context).width < 560
                  ? SizedBox(width: double.infinity, child: checkoutBtn)
                  : checkoutBtn;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorHistoryTile(SchoolVisitorRecord v) {
    final inStr = DateFormat('HH:mm').format(v.entryTime);
    final outStr = v.exitTime != null
        ? DateFormat('HH:mm').format(v.exitTime!)
        : 'İçeride';
    final inside = v.isInside;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: inside ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inside ? const Color(0xFF99F6E4) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: inside ? const Color(0xFFCCFBF1) : Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: inside
                    ? const Color(0xFF5EEAD4)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$inStr → $outStr',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.4,
                    color: inside
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  v.stayDurationLabel,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      v.visitorName,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.2,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '(${v.visitorCategory}${v.badgeNo.isNotEmpty ? " • Kart: ${v.badgeNo}" : ""}${v.vehiclePlate.isNotEmpty ? " • Plaka: ${v.vehiclePlate}" : ""})',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${v.targetUnit}${v.hostStaffName.isNotEmpty ? " (${v.hostStaffName})" : ""}'
                  ' • Sebep: ${v.visitReason}'
                  ' • Kayıt: ${v.checkedInByName}'
                  '${v.exitNote.isNotEmpty ? " • Çıkış Notu: ${v.exitNote}" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11.3,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (inside)
            TextButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _confirmVisitorCheckOutDialog(v),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0D9488),
              ),
              icon: const Icon(Icons.logout_rounded, size: 17),
              label: const Text(
                'Çıkış Yap',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORTAK PREMIUM FORM BİLEŞENLERİ (ALT ALTA ÇEKLİST & METİN ALANI)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCounterChip({
    required String label,
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.3,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildVerticalSingleChecklist({
    required String label,
    required Color accentColor,
    required String selectedValue,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.3,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                Builder(
                  builder: (_) {
                    final item = options[i];
                    final sel = selectedValue == item;
                    return Material(
                      color: sel
                          ? accentColor.withValues(alpha: 0.07)
                          : Colors.white,
                      child: InkWell(
                        onTap: () => onSelected(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                sel
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 20,
                                color: sel
                                    ? accentColor
                                    : const Color(0xFFCBD5E1),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.8,
                                    fontWeight: sel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: sel
                                        ? accentColor
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (sel)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Seçili',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    String? badgeText,
    required String hint,
    required IconData icon,
    required Color accentColor,
    ValueChanged<String>? onChanged,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.inter(
            fontSize: 13.2,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 12.6,
              color: const Color(0xFF94A3B8),
            ),
            prefixIcon: Icon(icon, size: 19, color: accentColor),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12.5,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.7),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStandaloneActions() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final impersonating = UserPermissionService.isImpersonating();

    return [
      if (impersonating)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton.icon(
            onPressed: _exitImpersonation,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFFF7ED),
              foregroundColor: const Color(0xFFC2410C),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFFDBA74)),
              ),
            ),
            icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
            label: Text(
              isMobile ? 'Yöneticiye Dön' : 'Yönetici Hesabına Dön',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      PopupMenuButton<String>(
        tooltip: 'Hesap ve Oturum İşlemleri',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (val) {
          if (val == 'profile') {
            Navigator.pushNamed(context, '/profile-settings');
          } else if (val == 'exit_imp') {
            _exitImpersonation();
          } else if (val == 'logout') {
            _confirmStandaloneLogout();
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _securityActorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Güvenlik Kapı Portalı',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'profile',
            child: Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: Color(0xFF334155),
                ),
                SizedBox(width: 10),
                Text(
                  'Profil ve Şifre Ayarları',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          if (impersonating)
            const PopupMenuItem<String>(
              value: 'exit_imp',
              child: Row(
                children: [
                  Icon(Icons.undo_rounded, size: 18, color: Color(0xFFC2410C)),
                  SizedBox(width: 10),
                  Text(
                    'Yönetici Hesabına Dön',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC2626)),
                SizedBox(width: 10),
                Text(
                  'Güvenli Çıkış Yap',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 11,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_rounded,
                size: 16,
                color: Color(0xFF0284C7),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _securityActorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0C4A6E),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF0284C7),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _exitImpersonation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    await prefs.setString('active_portal', 'manager');
    UserPermissionService.clearCache();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/school-dashboard', (_) => false);
  }

  Future<void> _confirmStandaloneLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Güvenlik Kapı oturumunuzu kapatmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_portal');
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    UserPermissionService.clearCache();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/school-login', (_) => false);
  }
}
