import 'package:edukn/services/term_service.dart';
import 'package:edukn/services/user_permission_service.dart';
import 'package:flutter/foundation.dart';

import '../models/odak_models.dart';
import '../repository/odak_repository.dart';
import '../services/odak_engine.dart';

/// ODAK-64 durum yönetimi (Provider + ChangeNotifier).
class OdakController extends ChangeNotifier {
  final String institutionId;
  final OdakRepository _repo;

  OdakController(this.institutionId, {OdakRepository? repository})
      : _repo = repository ?? OdakRepository();

  bool _disposed = false;

  // Sınav seçimi
  List<OdakExamInfo> exams = [];
  bool loadingExams = true;
  bool loadingExam = false;
  String? error;
  String? selectedExamId;
  OdakExamData? examData;

  // Ayarlar
  Map<String, int> weights = {};
  int weeks = 8;
  int hoursPerWeek = 4;
  int maxClassSize = 20;

  /// Verilecek dersler ve haftalık saatleri (seçili olmayan ders map'te yoktur).
  Map<String, int> lessonHours = {};
  bool _hoursTouched = false;

  int get allocatedHours => lessonHours.values.fold(0, (a, b) => a + b);
  int get remainingHours => hoursPerWeek - allocatedHours;

  // Sonuç
  List<OdakClassGroup> groups = [];
  OdakAnalyzer? analyzer;
  bool generated = false;

  /// Ayarlar son oluşturmadan sonra değiştiyse true.
  bool stale = false;

  List<String> get subjects => examData?.subjects ?? const [];
  int get totalWeight => weights.values.fold(0, (a, b) => a + b);
  int get studentCount => examData?.results.length ?? 0;
  bool get canGenerate =>
      examData != null &&
      examData!.results.isNotEmpty &&
      totalWeight == 100 &&
      lessonHours.isNotEmpty &&
      allocatedHours == hoursPerWeek &&
      maxClassSize > 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> init() async {
    loadingExams = true;
    error = null;
    _notify();
    try {
      final termId = await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();
      final userData = await UserPermissionService.loadUserData();
      final instId =
          (userData?['institutionId'] ?? institutionId).toString();
      exams = await _repo.loadExams(instId, termId);
    } catch (e) {
      error = 'Sınavlar yüklenemedi: $e';
    }
    loadingExams = false;
    _notify();
  }

  Future<void> selectExam(String? id) async {
    selectedExamId = id;
    examData = null;
    weights = {};
    groups = [];
    analyzer = null;
    generated = false;
    stale = false;
    error = null;
    if (id == null) {
      _notify();
      return;
    }
    loadingExam = true;
    _notify();
    try {
      final data = await _repo.loadExam(id);
      examData = data;
      weights = OdakEngine.defaultWeights(data.subjects);
      _hoursTouched = false;
      _autoSplitHours();
    } catch (e) {
      error = 'Sınav verisi yüklenemedi: $e';
    }
    loadingExam = false;
    _notify();
  }

  /// Bir veya birden fazla sınav seçer. Birden fazlaysa sonuçlar öğrenci
  /// bazında birleştirilir (birleşik değerlendirme).
  Future<void> selectExams(List<String> ids) async {
    if (ids.length <= 1) {
      return selectExam(ids.isEmpty ? null : ids.first);
    }
    selectedExamId = ids.first;
    examData = null;
    weights = {};
    groups = [];
    analyzer = null;
    generated = false;
    stale = false;
    error = null;
    loadingExam = true;
    _notify();
    try {
      final loaded = <OdakExamData>[];
      for (final id in ids) {
        loaded.add(await _repo.loadExam(id));
      }
      final data = OdakRepository.merge(loaded);
      examData = data;
      weights = OdakEngine.defaultWeights(data.subjects);
      _hoursTouched = false;
      _autoSplitHours();
    } catch (e) {
      error = 'Sınav verisi yüklenemedi: $e';
    }
    loadingExam = false;
    _notify();
  }


  void setWeight(String subject, int value) {
    if (!weights.containsKey(subject)) return;
    weights = OdakEngine.rebalance(weights, subject, value);
    if (!_hoursTouched) _autoSplitHours();
    if (generated) stale = true;
    _notify();
  }

  /// Ders ağırlıklarına göre haftalık saati otomatik böler (kullanıcı dokunmadıysa).
  void _autoSplitHours() {
    final active = weights.entries.where((e) => e.value > 0).toList();
    final result = <String, int>{};
    if (active.isNotEmpty && hoursPerWeek > 0) {
      final raws = {for (final e in active) e.key: hoursPerWeek * e.value / 100.0};
      var assigned = 0;
      for (final e in raws.entries) {
        result[e.key] = e.value.floor();
        assigned += result[e.key]!;
      }
      var diff = hoursPerWeek - assigned;
      final order = raws.entries.toList()
        ..sort((a, b) =>
            (b.value - b.value.floor()).compareTo(a.value - a.value.floor()));
      var i = 0;
      while (diff > 0 && order.isNotEmpty) {
        final k = order[i % order.length].key;
        result[k] = result[k]! + 1;
        diff--;
        i++;
      }
      result.removeWhere((_, v) => v <= 0);
    }
    lessonHours = result;
  }

  void toggleLesson(String subject, bool on) {
    _hoursTouched = true;
    if (on) {
      lessonHours = {...lessonHours, subject: remainingHours > 0 ? remainingHours : 1};
    } else {
      lessonHours = {...lessonHours}..remove(subject);
    }
    if (generated) stale = true;
    _notify();
  }

  void setLessonHours(String subject, int hours) {
    if (!lessonHours.containsKey(subject)) return;
    _hoursTouched = true;
    lessonHours = {...lessonHours, subject: hours < 1 ? 1 : hours};
    if (generated) stale = true;
    _notify();
  }

  void autoDistributeHours() {
    _hoursTouched = false;
    _autoSplitHours();
    if (generated) stale = true;
    _notify();
  }

  void setWeeks(int v) {
    weeks = v < 1 ? 1 : v;
    if (generated) stale = true;
    _notify();
  }

  void setHoursPerWeek(int v) {
    hoursPerWeek = v < 1 ? 1 : v;
    if (!_hoursTouched) _autoSplitHours();
    if (generated) stale = true;
    _notify();
  }

  void setMaxClassSize(int v) {
    maxClassSize = v < 1 ? 1 : v;
    if (generated) stale = true;
    _notify();
  }

  void generate() {
    final data = examData;
    if (data == null || !canGenerate) return;
    final ranked = OdakEngine.rank(data.results, weights);
    groups = OdakEngine.split(ranked, maxClassSize);
    analyzer = OdakAnalyzer(
      groups: groups,
      weights: Map<String, int>.from(weights),
      outcomes: data.outcomes,
      weeks: weeks,
      hoursPerWeek: hoursPerWeek,
      lessonHours: Map<String, int>.from(lessonHours),
      riskBelowScore: 50,
    );
    generated = true;
    stale = false;
    _notify();
  }
}
