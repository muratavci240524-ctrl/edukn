import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../../../models/assessment/outcome_list_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../utils/drive_image_helper.dart';
import '../../../../utils/difficulty_scale.dart';
import '../../../../utils/gercek_kazanim_mapper.dart';
import 'google_sheets_seed_data.dart';

class ParsedSheetQuestionRow {
  final int rowIndex;
  final int questionNo;
  final String classLevel;
  final String subject;
  final String topic;
  final String legacyOutcome;
  final String k12Code;
  final String k12OutcomeRaw;
  final String kazanimCode;
  final String k12Description;
  final String questionType;
  final String rawDifficulty;
  final String correctAnswer;
  final String fileName;
  final String rawImageUrl;
  final String? driveFileId;
  final String curriculumSource;

  /// Tablodaki "Kazanım" hücresinden ayrıştırılan saf kazanım metni
  /// (ör. "Bağlamdan hareketle bilmediği kelime ve kelime gruplarının anlamını tahmin eder.").
  final String kazanimText;

  /// Kazanım metninin sonundaki parantez içi alt konu (ör. "Gerçek ve Mecaz Anlam").
  /// Tabloda ayrı bir "Alt Konu" sütunu varsa onun değeri kullanılır.
  final String subTopic;

  /// Tablodaki açık "Alt Konu" sütununun değeri (ör. "Mutlak Değer").
  /// Soru Havuzu sol listesinde Konu → Alt Konu ağacı bu alana göre kurulur.
  final String altKonu;

  /// Outcome matched from institution's `outcome_lists` via `kazanimCode`.
  String? matchedInstitutionOutcomeDesc;
  String? matchedInstitutionOutcomeCode;
  bool isMatchedInOutcomeList;
  bool selected;

  ParsedSheetQuestionRow({
    required this.rowIndex,
    required this.questionNo,
    required this.classLevel,
    required this.subject,
    required this.topic,
    required this.legacyOutcome,
    required this.k12Code,
    required this.k12OutcomeRaw,
    required this.kazanimCode,
    required this.k12Description,
    required this.questionType,
    required this.rawDifficulty,
    required this.correctAnswer,
    required this.fileName,
    required this.rawImageUrl,
    required this.driveFileId,
    required this.curriculumSource,
    this.kazanimText = '',
    this.subTopic = '',
    this.altKonu = '',
    this.matchedInstitutionOutcomeDesc,
    this.matchedInstitutionOutcomeCode,
    this.isMatchedInOutcomeList = false,
    this.selected = true,
  });

  /// Soruya kaydedilen kazanım metni: tablodaki "Kazanım" sütununun KOD'dan ayrılmış metni.
  String get effectiveOutcome {
    if (kazanimText.trim().isNotEmpty) return kazanimText.trim();
    if (legacyOutcome.trim().isNotEmpty) return legacyOutcome.trim();
    return topic.trim();
  }

  /// Soruya kaydedilen kazanım kodu: tablodaki "Kazanım" sütununun başındaki kod (ör. "T.7.3.5").
  String get effectiveKazanimCode => kazanimCode.trim();

  /// "T.7.3.5. Bağlamdan hareketle ... eder. (Gerçek ve Mecaz Anlam)" veya
  /// "Metinden hareketle ... yapabilme (Gerçek ve Mecaz Anlam)" →
  /// (code, text, sub) olarak ayırır (iç içe parantez destekli).
  static ({String code, String text, String sub}) splitKazanimCell(
    String raw, {
    String explicitCode = '',
  }) {
    final s = GercekKazanimMapper.splitOutcomeTextAndSubTopic(
      raw,
      explicitCode: explicitCode,
    );
    return (code: s.code, text: s.text, sub: s.sub);
  }

  /// Tablodaki 1–5 zorluk seviyesi (1 = Çok Kolay … 5 = Çok Zor). Boş / "Belirtilmemiş" → 3 (Orta).
  int get difficultyLevel {
    final d = int.tryParse(rawDifficulty.replaceAll(RegExp(r'[^0-9]'), ''));
    if (d == null) return 3;
    return d.clamp(1, 5);
  }

  /// Hata Kitapçığı ile aynı 5 aşamalı ölçekte havuz `difficulty` değeri.
  double get difficultyScore => DifficultyScale.scoreForLevel(difficultyLevel);
}

class GoogleSheetsPoolImportDialog extends StatefulWidget {
  final String institutionId;
  final List<OutcomeList> existingOutcomeLists;

  const GoogleSheetsPoolImportDialog({
    super.key,
    required this.institutionId,
    required this.existingOutcomeLists,
  });

  @override
  State<GoogleSheetsPoolImportDialog> createState() =>
      _GoogleSheetsPoolImportDialogState();
}

class _GoogleSheetsPoolImportDialogState
    extends State<GoogleSheetsPoolImportDialog> {
  final TextEditingController _urlCtrl = TextEditingController(
    text: kDefaultQuestionPoolSheetUrl,
  );
  final TextEditingController _pasteCtrl = TextEditingController();

  bool _showPasteBox = false;
  bool _isLoadingSheet = false;
  bool _isImporting = false;
  String? _loadInfoMessage;
  bool _loadInfoIsWarning = false;

  /// Filter: 'all', 'multiple_choice', 'exercise'
  String _questionTypeFilter = 'all';


  /// Tablodaki Gerçek Kazanımları (kod + metin) kurumun `outcome_lists` listesine de ekle / eşleştir.
  bool _autoSyncOutcomeLists = true;

  /// Attempt to pre-fetch Drive image bytes (`base64Image`) during import.
  /// Default is false so images stay on Google Drive without consuming Firebase storage.
  bool _tryCacheDriveImagesAsBase64 = false;

  int _importCurrent = 0;
  int _importTotal = 0;
  String _importStatusText = '';

  List<ParsedSheetQuestionRow> _allParsedRows = [];

  /// Bu tablodan daha önce havuza aktarılmış soru sayısı (`sourceSheetId` eşleşmesi).
  int? _alreadyImportedCount;

  /// Aktarım sonrası, tabloda artık bulunmayan (silinmiş / numarası değişmiş) soruları havuzdan da kaldır.
  bool _syncRemoveMissing = false;

  bool _isDeleting = false;

  String get _currentSheetId =>
      _extractSheetIdAndGid(_urlCtrl.text).sheetId ?? kDefaultQuestionPoolSheetId;

  CollectionReference<Map<String, dynamic>> get _poolCol => FirebaseFirestore.instance
      .collection('trial_exams')
      .doc('pool_${widget.institutionId}')
      .collection('questions_pool');

  /// Her tablo satırı için sabit doküman kimliği: aynı tablo tekrar aktarılınca soru
  /// kopyalanmaz, üzerine güncellenir.
  String _docIdForRow(ParsedSheetQuestionRow row, String sheetId) {
    final sheetShort = sheetId.length > 10 ? sheetId.substring(0, 10) : sheetId;
    final normSub = _normTr(row.subject).replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normCls = _normTr(row.classLevel).replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 'sheet_${sheetShort}_${normCls}_${normSub}_q${row.questionNo}';
  }

  Future<void> _refreshImportedCount() async {
    try {
      final snap = await _poolCol.where('sourceSheetId', isEqualTo: _currentSheetId).get();
      if (mounted) setState(() => _alreadyImportedCount = snap.size);
    } catch (_) {}
  }

  Future<int> _deleteDocs(List<DocumentReference<Map<String, dynamic>>> refs) async {
    int deleted = 0;
    for (int i = 0; i < refs.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final r in refs.sublist(i, i + 400 > refs.length ? refs.length : i + 400)) {
        batch.delete(r);
        deleted++;
      }
      await batch.commit();
    }
    return deleted;
  }

  Future<void> _deleteAllImportedFromSheet() async {
    final count = _alreadyImportedCount ?? 0;
    if (count == 0) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tablodan Aktarılan Soruları Sil'),
        content: Text(
          'Bu Google Tablodan Soru Havuzuna aktarılmış $count soru kalıcı olarak silinecek.\n\n'
          'Google Tablonuz ve Drive görselleriniz SİLİNMEZ; istediğiniz zaman tekrar aktarabilirsiniz.\n'
          'Elle kırpılarak eklenen diğer havuz soruları etkilenmez.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('$count Soruyu Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final snap = await _poolCol.where('sourceSheetId', isEqualTo: _currentSheetId).get();
      final deleted = await _deleteDocs(snap.docs.map((d) => d.reference).toList());
      await _refreshImportedCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Tablodan aktarılan $deleted soru havuzdan silindi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Silme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFromUrlOrFallback(initialLoad: true);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  static String _canonicalSubject(String raw) {
    final n = _normTr(raw);
    if (n.contains('turkce')) return 'Türkçe';
    if (n.contains('matematik') || n == 'mat') return 'Matematik';
    if (n.contains('fen')) return 'Fen Bilimleri';
    if (n.contains('inkilap')) return 'T.C. İnkılap Tarihi';
    if (n.contains('sosyal')) return 'Sosyal Bilgiler';
    if (n.contains('din')) return 'Din Kültürü ve Ahlak Bilgisi';
    if (n.contains('ingilizce') || n.contains('yabanci')) return 'İngilizce';
    if (n.contains('fizik')) return 'Fizik';
    if (n.contains('kimya')) return 'Kimya';
    if (n.contains('biyoloji')) return 'Biyoloji';
    if (n.contains('tarih')) return 'Tarih';
    if (n.contains('cografya')) return 'Coğrafya';
    return raw.trim().isEmpty ? 'Türkçe' : raw.trim();
  }

  static ({String? sheetId, String gid}) _extractSheetIdAndGid(String rawUrl) {
    final trimmed = rawUrl.trim();
    final idMatch = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    final gidMatch = RegExp(r'[?#&]gid=(\d+)').firstMatch(trimmed);
    final gid = gidMatch?.group(1) ?? '0';
    if (idMatch != null) {
      return (sheetId: idMatch.group(1), gid: gid);
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{25,60}$').hasMatch(trimmed)) {
      return (sheetId: trimmed, gid: gid);
    }
    return (sheetId: null, gid: gid);
  }

  /// RFC-4180 compliant CSV / TSV parser supporting quoted multiline cells.
  static List<List<String>> _parseDelimitedTable(String raw, {String? forceDelimiter}) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.trim().isEmpty) return const [];

    final String delimiter;
    if (forceDelimiter != null) {
      delimiter = forceDelimiter;
    } else {
      final firstLineEnd = text.indexOf('\n');
      final firstLine = firstLineEnd == -1 ? text : text.substring(0, firstLineEnd);
      final tabCount = '\t'.allMatches(firstLine).length;
      final commaCount = ','.allMatches(firstLine).length;
      delimiter = tabCount > commaCount ? '\t' : ',';
    }

    final List<List<String>> rows = [];
    List<String> currentRow = [];
    final StringBuffer cell = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == delimiter) {
          currentRow.add(cell.toString().trim());
          cell.clear();
        } else if (ch == '\n') {
          currentRow.add(cell.toString().trim());
          cell.clear();
          if (currentRow.any((c) => c.isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = [];
        } else {
          cell.write(ch);
        }
      }
    }
    currentRow.add(cell.toString().trim());
    if (currentRow.any((c) => c.isNotEmpty)) {
      rows.add(currentRow);
    }
    return rows;
  }

  Future<void> _loadFromUrlOrFallback({bool initialLoad = false}) async {
    setState(() {
      _isLoadingSheet = true;
      _loadInfoMessage = null;
      _loadInfoIsWarning = false;
    });

    try {
      if (_showPasteBox && _pasteCtrl.text.trim().isNotEmpty) {
        final matrix = _parseDelimitedTable(_pasteCtrl.text);
        _applyMatrix(
          matrix,
          sourceLabel: 'Yapıştırılan tablo verisinden yüklendi',
        );
        return;
      }

      final extracted = _extractSheetIdAndGid(_urlCtrl.text);
      final sheetId = extracted.sheetId;
      final gid = extracted.gid;

      if (sheetId == null || sheetId.isEmpty) {
        setState(() {
          _loadInfoMessage = 'Geçerli bir Google Sheets bağlantısı giriniz.';
          _loadInfoIsWarning = true;
        });
        return;
      }

      final builtInRows = kBuiltInQuestionPoolSheetsById[sheetId];
      List<List<String>>? liveMatrix;
      if (!initialLoad || builtInRows == null) {
        liveMatrix = await _tryFetchLiveSheetMatrix(sheetId, gid);
      }

      if (liveMatrix != null && liveMatrix.length > 1) {
        _applyMatrix(
          liveMatrix,
          sourceLabel: 'Google Sheets canlı bağlantısından (${liveMatrix.length - 1} soru) çekildi ✓',
        );
        return;
      }

      // Built-in verified dataset for the user's known sheets (Sözcükte Anlam & Cümlede Anlam)
      if (builtInRows != null) {
        _applyMatrix(
          builtInRows,
          sourceLabel:
              'Google Sheets ("Soru Havuzu" • ${builtInRows.length - 1} soru) yüklendi ✓',
        );
        // Also attempt background refresh if initialLoad was true
        if (initialLoad) {
          unawaited(_refreshLiveInBackground(sheetId, gid));
        }
        return;
      }

      setState(() {
        _loadInfoMessage =
            'Tablo bağlantısına doğrudan erişilemedi (tablo "Kısıtlı" olabilir). '
            'Google E-Tablolar\'da Paylaş -> "Bağlantıya sahip olan herkes" yapın veya "Tablo Verisini Yapıştır" seçeneğini kullanın.';
        _loadInfoIsWarning = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingSheet = false);
      }
    }
  }

  Future<void> _refreshLiveInBackground(String sheetId, String gid) async {
    final live = await _tryFetchLiveSheetMatrix(sheetId, gid);
    if (!mounted || live == null || live.length <= 1) return;
    _applyMatrix(
      live,
      sourceLabel:
          'Google Sheets canlı bağlantısından (${live.length - 1} soru) güncellendi ✓',
    );
  }

  Future<List<List<String>>?> _tryFetchLiveSheetMatrix(
    String sheetId,
    String gid,
  ) async {
    final gvizUrl =
        'https://docs.google.com/spreadsheets/d/$sheetId/gviz/tq?tqx=out:csv&gid=$gid';
    final exportUrl =
        'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv&gid=$gid';
    final candidates = [
      gvizUrl,
      exportUrl,
      'https://corsproxy.io/?${Uri.encodeComponent(gvizUrl)}',
    ];

    for (final url in candidates) {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final body = utf8.decode(res.bodyBytes, allowMalformed: true);
          if (body.trimLeft().startsWith('<!DOCTYPE') ||
              body.trimLeft().startsWith('<html')) {
            continue;
          }
          final parsed = _parseDelimitedTable(body, forceDelimiter: ',');
          if (parsed.length > 1 && parsed.first.length >= 4) {
            return parsed;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  void _applyMatrix(List<List<String>> matrix, {required String sourceLabel}) {
    if (matrix.isEmpty) return;

    final headers = matrix.first.map((h) => _normTr(h)).toList();
    int findCol(List<String> patterns, int fallback) {
      for (final p in patterns) {
        final idx = headers.indexWhere((h) => h.contains(p));
        if (idx != -1) return idx;
      }
      return fallback;
    }

    final colQNo = findCol(['soru no', 'soruno', 'no'], 0);
    final colClass = findCol(['sinif', 'seviye'], 1);
    final colSubject = findCol(['brans', 'ders'], 2);
    // "Konu" sütunu ("Alt Konu" sütunuyla karışmasın)
    int colTopic = headers.indexWhere(
      (h) => (h.contains('konu') || h.contains('unite')) && !h.contains('alt'),
    );
    if (colTopic == -1) colTopic = 3;
    // Yeni tablo yapısı: ayrı "Alt Konu" sütunu
    final int colAltKonu = headers.indexWhere(
      (h) =>
          h.contains('alt konu') ||
          h.contains('altkonu') ||
          h.contains('alt baslik'),
    );

    // Yeni tablo yapısı:
    // Col E (4): "Gerçek Kazanım Kodu (2026-2027 TYMM)"
    // Col F (5): "Gerçek Kazanım Açıklaması (MEB 2026-2027)"
    // Col G (6): "K12NET Havuz & Eski Müfredat Karşılığı"
    final int colGercekCode = headers.indexWhere(
      (h) =>
          (h.contains('gercek') && h.contains('kod')) ||
          (h.contains('kazanim') && h.contains('kod') && !h.contains('k12')),
    );
    final int colGercekDesc = headers.indexWhere(
      (h) =>
          (h.contains('gercek') && (h.contains('aciklama') || h.contains('kazanim')) && !h.contains('kod')) ||
          (h.contains('kazanim aciklama')),
    );
    final int colK12Mapping = headers.indexWhere(
      (h) => h.contains('k12net') || h.contains('eski mufredat') || h.contains('karsiligi'),
    );

    // Eski tek sütunlu "Kazanım" desteği (yedek)
    final colLegacyOutcome = headers.indexWhere(
      (h) =>
          h.contains('kazanim') &&
          !h.contains('k12') &&
          !h.contains('gercek') &&
          !h.contains('kod'),
    );
    final colK12Code = findCol(['k12 kodu', 'k12 kod', 'k12code'], 5);
    final colK12Outcome = findCol(['k12 kazanim', 'k12net'], 6);
    final colQType = findCol(['soru turu', 'tur', 'tip'], 7);
    final colDiff = findCol(['zorluk'], 8);
    final colAns = findCol(['cevap', 'anahtar'], 9);
    final colFileName = findCol(['drive baglantisi', 'dosya'], 10);
    final colImageUrl = findCol(['dogrudan url', 'url', 'link'], 11);
    final colSource = findCol(['mufredat kayna', 'kaynak'], 12);

    String cellAt(List<String> row, int idx) {
      if (idx < 0 || idx >= row.length) return '';
      return row[idx].trim();
    }

    final List<ParsedSheetQuestionRow> parsed = [];
    for (int r = 1; r < matrix.length; r++) {
      final row = matrix[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final qNoRaw = cellAt(row, colQNo);
      final qNo = int.tryParse(qNoRaw.replaceAll(RegExp(r'[^0-9]'), '')) ?? r;
      final rawCls = cellAt(row, colClass);
      final classLevel = AssessmentService.normalizeClassLevel(
        rawCls.isNotEmpty ? rawCls : '7. Sınıf',
      );
      final subject = _canonicalSubject(cellAt(row, colSubject));
      final topic = cellAt(row, colTopic);
      final altKonu = colAltKonu != -1 ? cellAt(row, colAltKonu) : '';

      final String rawGercekCode =
          colGercekCode != -1 ? cellAt(row, colGercekCode) : '';
      final String rawGercekDesc =
          colGercekDesc != -1 ? cellAt(row, colGercekDesc) : '';
      final String rawK12Mapping =
          colK12Mapping != -1 ? cellAt(row, colK12Mapping) : '';

      final legacyOutcome = colLegacyOutcome != -1
          ? cellAt(row, colLegacyOutcome)
          : rawK12Mapping;
      final k12Code = rawK12Mapping.isNotEmpty
          ? rawK12Mapping
          : cellAt(row, colK12Code);
      final k12OutcomeRaw = rawK12Mapping.isNotEmpty
          ? rawK12Mapping
          : cellAt(row, colK12Outcome);
      final questionType = cellAt(row, colQType).isNotEmpty
          ? cellAt(row, colQType)
          : 'Çoktan Seçmeli';
      final rawDiff = cellAt(row, colDiff);
      final rawAns = cellAt(row, colAns).toUpperCase();
      final correctAnswer = ['A', 'B', 'C', 'D', 'E'].contains(rawAns)
          ? rawAns
          : (rawAns.isEmpty ? '-' : rawAns);
      final fileName = cellAt(row, colFileName);
      String rawImageUrl = cellAt(row, colImageUrl);
      String? extractedDriveId = DriveImageHelper.extractDriveFileId(rawImageUrl) ??
          DriveImageHelper.extractDriveFileId(fileName);
      if (extractedDriveId == null) {
        for (final c in row) {
          final id = DriveImageHelper.extractDriveFileId(c);
          if (id != null) {
            extractedDriveId = id;
            if (rawImageUrl.isEmpty) rawImageUrl = c.trim();
            break;
          }
        }
      }
      if (rawImageUrl.isEmpty && extractedDriveId != null) {
        rawImageUrl = 'https://drive.google.com/uc?export=view&id=$extractedDriveId';
      }
      final curriculumSource = cellAt(row, colSource);

      // "Gerçek Kazanım Kodu (2026-2027 TYMM)" ve "Gerçek Kazanım Açıklaması (MEB 2026-2027)" ayrıştırması
      final ({String code, String text, String sub}) split;
      if (rawGercekDesc.isNotEmpty || rawGercekCode.isNotEmpty) {
        split = ParsedSheetQuestionRow.splitKazanimCell(
          rawGercekDesc,
          explicitCode: rawGercekCode,
        );
        GercekKazanimMapper.registerFromSheetRow(
          gercekCode: split.code,
          gercekBaseText: split.text,
          k12MappingCell: rawK12Mapping,
          topic: topic,
        );
      } else {
        final fallbackSplit = ParsedSheetQuestionRow.splitKazanimCell(legacyOutcome);
        final resolved = GercekKazanimMapper.resolve(
          rawCode: fallbackSplit.code,
          rawOutcome: fallbackSplit.text,
          k12Code: k12Code,
          legacyOutcome: legacyOutcome,
          existingSubTopic: fallbackSplit.sub,
        );
        split = (code: resolved.code, text: resolved.description, sub: resolved.subTopic);
      }

      parsed.add(
        ParsedSheetQuestionRow(
          rowIndex: r,
          questionNo: qNo,
          classLevel: classLevel,
          subject: subject,
          topic: topic.isNotEmpty ? topic : 'Genel Konu',
          legacyOutcome: legacyOutcome,
          k12Code: '',
          k12OutcomeRaw: k12OutcomeRaw,
          kazanimCode: split.code,
          k12Description: '',
          kazanimText: split.text,
          subTopic: altKonu.isNotEmpty ? altKonu : split.sub,
          altKonu: altKonu,
          questionType: questionType,
          rawDifficulty: rawDiff,
          correctAnswer: correctAnswer,
          fileName: fileName,
          rawImageUrl: rawImageUrl,
          driveFileId: extractedDriveId,
          curriculumSource: curriculumSource,
          selected: true,
        ),
      );
    }

    setState(() {
      _allParsedRows = parsed;
      _loadInfoMessage = sourceLabel;
      _loadInfoIsWarning = false;
      _applyTypeFilterSelection();
    });
    _refreshImportedCount();
  }

  List<ParsedSheetQuestionRow> get _visibleRows {
    return _allParsedRows.where((r) {
      if (_questionTypeFilter == 'multiple_choice') {
        return !_normTr(r.questionType).contains('egzersiz');
      }
      if (_questionTypeFilter == 'exercise') {
        return _normTr(r.questionType).contains('egzersiz');
      }
      return true;
    }).toList();
  }

  void _applyTypeFilterSelection() {
    for (final r in _allParsedRows) {
      if (_questionTypeFilter == 'multiple_choice') {
        r.selected = !_normTr(r.questionType).contains('egzersiz');
      } else if (_questionTypeFilter == 'exercise') {
        r.selected = _normTr(r.questionType).contains('egzersiz');
      } else {
        r.selected = true;
      }
    }
  }

  /// Ensures all topics (`depth: 1`) and K12 outcomes (`depth: 2`) in the imported rows
  /// exist in the institution's `outcome_lists` collection so `QuestionPoolScreen`,
  /// `TrialExamAnswerKeyScreen`, and `PersonalizedBookGeneratorService` match 100%.
  Future<int> _syncK12OutcomesToInstitutionLists(
    List<ParsedSheetQuestionRow> rowsToImport,
  ) async {
    if (rowsToImport.isEmpty) return 0;

    // Group rows by (classLevel, subject)
    final Map<String, List<ParsedSheetQuestionRow>> byGroup = {};
    for (final r in rowsToImport) {
      final key = '${r.classLevel}::${r.subject}';
      byGroup.putIfAbsent(key, () => []).add(r);
    }

    int newlySyncedOutcomes = 0;
    final col = FirebaseFirestore.instance.collection('outcome_lists');

    for (final entry in byGroup.entries) {
      final sample = entry.value.first;
      final cls = sample.classLevel;
      final sub = sample.subject;

      // Find existing OutcomeList for this (institutionId, classLevel, branchName)
      OutcomeList? targetList;
      for (final ol in widget.existingOutcomeLists) {
        if (_normTr(ol.classLevel) == _normTr(cls) &&
            _normTr(ol.branchName) == _normTr(sub)) {
          targetList = ol;
          break;
        }
      }

      final List<OutcomeItem> items = targetList != null
          ? List<OutcomeItem>.from(targetList.outcomes)
          : <OutcomeItem>[];

      bool changed = false;

      // 1) Mevcut listedeki K12 taslak kodlarını / metinlerini Gerçek Kazanımlara dönüştür
      for (int idx = 0; idx < items.length; idx++) {
        final cur = items[idx];
        if (cur.depth == 1) continue;
        final resolved = GercekKazanimMapper.resolve(
          rawCode: cur.code,
          rawOutcome: cur.description,
          k12Code: cur.k12Code,
        );
        if (resolved.code.isNotEmpty &&
            (cur.code != resolved.code ||
                cur.description != resolved.description ||
                cur.k12Code.isNotEmpty)) {
          items[idx] = OutcomeItem(
            code: resolved.code,
            description: resolved.description,
            depth: cur.depth,
            k12Code: '',
          );
          changed = true;
        }
      }

      // Group rows by topic (`Konu`)
      final Map<String, List<ParsedSheetQuestionRow>> byTopic = {};
      for (final r in entry.value) {
        final t = r.topic.trim().isNotEmpty ? r.topic.trim() : 'Genel Konu';
        byTopic.putIfAbsent(t, () => []).add(r);
      }

      for (final topicEntry in byTopic.entries) {
        final topicName = topicEntry.key;
        int topicIdx = items.indexWhere(
          (i) => i.depth == 1 && _normTr(i.description) == _normTr(topicName),
        );
        if (topicIdx == -1) {
          items.add(
            OutcomeItem(
              code: '',
              description: topicName,
              depth: 1,
              k12Code: '',
            ),
          );
          topicIdx = items.length - 1;
          changed = true;
        }

        for (final r in topicEntry.value) {
          final code = r.effectiveKazanimCode;
          final desc = r.effectiveOutcome;
          if (desc.isEmpty) continue;

          // Bu Konu başlığının (`depth: 1`) altındaki alt kazanım aralığını bul: [topicIdx + 1 .. topicEndIdx)
          // Böylece birden fazla konuda ortak olan kazanımlar (ör. T.O.7.21 hem Sözcükte Anlam hem Cümlede Anlam)
          // her konunun kendi başlığı altında da yer alır.
          int topicEndIdx = topicIdx + 1;
          while (topicEndIdx < items.length && items[topicEndIdx].depth != 1) {
            topicEndIdx++;
          }

          int existingIdx = -1;
          for (int k = topicIdx + 1; k < topicEndIdx; k++) {
            final i = items[k];
            if ((code.isNotEmpty && _normTr(i.code) == _normTr(code)) ||
                _normTr(i.description) == _normTr(desc)) {
              existingIdx = k;
              break;
            }
          }

          if (existingIdx != -1) {
            final cur = items[existingIdx];
            r.matchedInstitutionOutcomeDesc = desc;
            r.matchedInstitutionOutcomeCode = code;
            if (cur.code.trim() != code ||
                cur.description.trim() != desc ||
                cur.k12Code.isNotEmpty) {
              items[existingIdx] = OutcomeItem(
                code: code.isNotEmpty ? code : cur.code.trim(),
                description: desc,
                depth: cur.depth,
                k12Code: '',
              );
              changed = true;
            }
          } else {
            // Insert right under its topic group (`depth: 1`)
            items.insert(
              topicEndIdx,
              OutcomeItem(
                code: code,
                description: desc,
                depth: 2,
                k12Code: '',
              ),
            );
            r.matchedInstitutionOutcomeDesc = desc;
            r.matchedInstitutionOutcomeCode = code;
            newlySyncedOutcomes++;
            changed = true;
          }
        }
      }

      if (changed) {
        if (targetList != null && targetList.id.isNotEmpty) {
          await col.doc(targetList.id).update({
            'outcomes': items.map((e) => e.toMap()).toList(),
          });
        } else {
          final docRef = col.doc();
          final newList = OutcomeList(
            id: docRef.id,
            institutionId: widget.institutionId,
            classLevel: cls,
            branchName: sub,
            name: '$cls $sub Kazanım Listesi',
            outcomes: items,
            isActive: true,
          );
          await docRef.set(newList.toMap());
        }
      }
    }

    return newlySyncedOutcomes;
  }

  Future<void> _importSelectedQuestions() async {
    final toImport = _visibleRows.where((r) => r.selected).toList();
    if (toImport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Lütfen aktarılacak en az bir soru seçiniz.'),
        ),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _importCurrent = 0;
      _importTotal = toImport.length;
      _importStatusText = 'Kazanımlar hazırlanıyor...';
    });

    try {
      int syncedOutcomeCount = 0;
      if (_autoSyncOutcomeLists) {
        syncedOutcomeCount = await _syncK12OutcomesToInstitutionLists(toImport);
      }

      final extracted = _extractSheetIdAndGid(_urlCtrl.text);
      final sheetId = extracted.sheetId ?? kDefaultQuestionPoolSheetId;

      final poolDocId = 'pool_${widget.institutionId}';
      final poolDocRef = FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(poolDocId);

      await poolDocRef.set({
        'isPoolContainer': true,
        'institutionId': widget.institutionId,
        'name': 'Soru Havuzu',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final poolCol = poolDocRef.collection('questions_pool');

      // Bu tablodan daha önce aktarılmış sorular (tekrar aktarımda güncelleme + senkron silme için)
      final existingSnap =
          await poolCol.where('sourceSheetId', isEqualTo: sheetId).get();
      final Set<String> manualWideIds = existingSnap.docs
          .where((d) => d.data()['isWideManual'] == true)
          .map((d) => d.id)
          .toSet();
      int updatedCount = 0;
      final Set<String> existingIds = existingSnap.docs.map((d) => d.id).toSet();

      int importedCount = 0;
      int cachedBase64Count = 0;
      const int chunkSize = 6;

      for (int i = 0; i < toImport.length; i += chunkSize) {
        final slice = toImport.sublist(
          i,
          (i + chunkSize > toImport.length) ? toImport.length : i + chunkSize,
        );

        if (mounted) {
          setState(() {
            _importCurrent = i;
            _importStatusText =
                'Sorular aktarılıyor (${i + 1} - ${i + slice.length} / ${toImport.length})...';
          });
        }

        // Optionally try to fetch Drive bytes in parallel for this chunk
        final Map<int, String> base64ByRow = {};
        if (_tryCacheDriveImagesAsBase64) {
          await Future.wait(
            slice.map((row) async {
              final bytes = await DriveImageHelper.fetchImageBytes(
                row.rawImageUrl,
                driveFileId: row.driveFileId,
                perTryTimeout: const Duration(seconds: 3),
              );
              if (bytes != null && bytes.length < 750 * 1024) {
                base64ByRow[row.questionNo] = base64Encode(bytes);
              }
            }),
          );
        }

        // Görselin en/boy oranını ölçüp soru genişliğini (1 / 2 Sütun) otomatik belirle
        final Map<int, Size> sizeByRow = {};
        await Future.wait(
          slice.map((row) async {
            final size = await DriveImageHelper.getImageSize(
              base64Image: base64ByRow[row.questionNo],
              imageUrl: row.rawImageUrl,
              driveFileId: row.driveFileId,
            );
            if (size != null) sizeByRow[row.questionNo] = size;
          }),
        );

        final batch = FirebaseFirestore.instance.batch();
        for (final row in slice) {
          final docId = _docIdForRow(row, sheetId);
          if (existingIds.contains(docId)) updatedCount++;
          final bool keepManualWide = manualWideIds.contains(docId);

          final normalizedImgUrl = DriveImageHelper.normalizeDriveImageUrl(
            row.rawImageUrl,
            driveFileId: row.driveFileId,
          );
          final cachedB64 = base64ByRow[row.questionNo];
          if (cachedB64 != null) cachedBase64Count++;

          final Map<String, dynamic> payload = {
            'subject': row.subject,
            'classLevel': row.classLevel,
            'questionNo': row.questionNo,
            'correctAnswer': row.correctAnswer,
            'difficulty': row.difficultyScore,
            'difficultyLevel': row.difficultyLevel,
            'difficultyScaleVersion': 2,
            'rawDifficultyLevel': row.rawDifficulty,
            'topic': row.topic,
            'outcome': row.effectiveOutcome,
            'kazanimCode': row.effectiveKazanimCode,
            'subTopic': row.subTopic,
            // Tablodaki "Alt Konu" sütunu (sol listede Konu → Alt Konu ağacı için)
            'altKonu': row.altKonu.isNotEmpty ? row.altKonu : FieldValue.delete(),
            // K12 kodu/kazanımı artık kullanılmıyor: eski aktarımlardan kalan değerleri temizle
            'k12Code': FieldValue.delete(),
            'k12OutcomeFull': FieldValue.delete(),
            'legacyOutcome': row.legacyOutcome,
            'questionType': row.questionType,
            'curriculumSource': row.curriculumSource,
            'fileName': row.fileName,
            'driveFileId': row.driveFileId,
            'rawDriveUrl': row.rawImageUrl,
            'imageUrl': normalizedImgUrl,
            'examName': 'Google Tablo (${row.classLevel} ${row.subject})',
            'sourceType': 'google_sheets',
            'sourceSheetId': sheetId,
            if (!keepManualWide)
              'isWide': sizeByRow[row.questionNo] != null
                  ? DriveImageHelper.shouldBeWide(sizeByRow[row.questionNo]!)
                  : false,
            if (sizeByRow[row.questionNo] != null) ...{
              'imageWidth': sizeByRow[row.questionNo]!.width,
              'imageHeight': sizeByRow[row.questionNo]!.height,
              'autoWideChecked': true,
              'autoWideVersion': DriveImageHelper.kAutoWideVersion,
            } else
              'autoWideChecked': false,
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (cachedB64 != null) {
            payload['base64Image'] = cachedB64;
          }

          batch.set(poolCol.doc(docId), payload, SetOptions(merge: true));
          importedCount++;
        }

        await batch.commit();
      }

      // Senkronizasyon: tabloda artık olmayan (silinmiş / numarası değişmiş) soruları havuzdan kaldır
      int removedCount = 0;
      if (_syncRemoveMissing) {
        if (mounted) {
          setState(() => _importStatusText = 'Tabloda olmayan eski sorular temizleniyor...');
        }
        final Set<String> validIds =
            _allParsedRows.map((r) => _docIdForRow(r, sheetId)).toSet();
        final stale = existingSnap.docs
            .where((d) => !validIds.contains(d.id))
            .map((d) => d.reference)
            .toList();
        removedCount = await _deleteDocs(stale);
      }

      if (mounted) {
        Navigator.pop(context, {
          'importedCount': importedCount,
          'updatedCount': updatedCount,
          'removedCount': removedCount,
          'syncedOutcomeCount': syncedOutcomeCount,
          'cachedBase64Count': cachedBase64Count,
          'classLevel': toImport.first.classLevel,
          'subject': toImport.first.subject,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Aktarım sırasında hata oluştu: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    final selectedCount = visible.where((r) => r.selected).length;
    final uniqueK12Codes = visible
        .map((r) => r.effectiveKazanimCode.isNotEmpty
            ? '${r.effectiveKazanimCode} ${r.effectiveOutcome}'
            : r.effectiveOutcome)
        .where((c) => c.isNotEmpty)
        .toSet();
    final mcCount = _allParsedRows
        .where((r) => !_normTr(r.questionType).contains('egzersiz'))
        .length;
    final exCount = _allParsedRows
        .where((r) => _normTr(r.questionType).contains('egzersiz'))
        .length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── ÜST BAŞLIK BANNER ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF4F46E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.table_chart_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Tablodan (Sheets) Soru Havuzuna Aktar',
                          style: GoogleFonts.outfit(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kazanım Kodu ve Metni, Zorluk, Cevap Anahtarı ve Drive Görsellerini Otomatik Aktarır',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isImporting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            // ── GÖVDE ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Google Sheets Link Satırı
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlCtrl,
                            enabled: !_isImporting,
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Google E-Tablo (Sheets) Bağlantısı',
                              hintText:
                                  'https://docs.google.com/spreadsheets/d/.../edit?gid=0',
                              prefixIcon: const Icon(
                                Icons.link_rounded,
                                color: Color(0xFF0F766E),
                              ),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: _urlCtrl.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Varsayılan Tabloyu Yükle',
                                      icon: const Icon(Icons.restore_rounded, size: 18),
                                      onPressed: _isImporting
                                          ? null
                                          : () {
                                              _urlCtrl.text =
                                                  kDefaultQuestionPoolSheetUrl;
                                              _loadFromUrlOrFallback();
                                            },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => _loadFromUrlOrFallback(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: (_isLoadingSheet || _isImporting)
                              ? null
                              : () => _loadFromUrlOrFallback(),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isLoadingSheet
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('Tabloyu Oku'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isImporting
                              ? null
                              : () => setState(() => _showPasteBox = !_showPasteBox),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            _showPasteBox
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.content_paste_rounded,
                            size: 17,
                          ),
                          label: const Text(
                            'Veri Yapıştır',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),

                    if (_showPasteBox) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pasteCtrl,
                        maxLines: 3,
                        style: GoogleFonts.inter(fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              'Gizli bir Google Tablodaki satırları seçip (Ctrl+C) buraya yapıştırabilirsiniz (Ctrl+V)...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          suffixIcon: TextButton(
                            onPressed: () => _loadFromUrlOrFallback(),
                            child: const Text('Yapıştırılanı Çözümle'),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Kayıtlı Konu Tabloları:',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.menu_book_rounded, size: 15),
                          label: const Text(
                            '7. Sınıf Türkçe • Sözcükte Anlam (108 Soru)',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _isImporting
                              ? null
                              : () {
                                  _urlCtrl.text = kDefaultQuestionPoolSheetUrl;
                                  _loadFromUrlOrFallback();
                                },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.short_text_rounded, size: 15),
                          label: const Text(
                            '7. Sınıf Türkçe • Cümlede Anlam (34 Soru)',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _isImporting
                              ? null
                              : () {
                                  _urlCtrl.text = kCumledeAnlamQuestionPoolSheetUrl;
                                  _loadFromUrlOrFallback();
                                },
                        ),
                      ],
                    ),

                    if (_loadInfoMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _loadInfoIsWarning
                              ? Colors.amber.shade50
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _loadInfoIsWarning
                                ? Colors.amber.shade300
                                : Colors.teal.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _loadInfoIsWarning
                                  ? Icons.warning_amber_rounded
                                  : Icons.verified_rounded,
                              size: 17,
                              color: _loadInfoIsWarning
                                  ? Colors.amber.shade900
                                  : Colors.teal.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _loadInfoMessage!,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _loadInfoIsWarning
                                      ? Colors.amber.shade900
                                      : Colors.teal.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // 2. Özet İstatistik Kartları + Soru Türü Filtresi
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildFilterChip(
                          label: 'Tümü (${_allParsedRows.length})',
                          selected: _questionTypeFilter == 'all',
                          onTap: () => setState(() {
                            _questionTypeFilter = 'all';
                            _applyTypeFilterSelection();
                          }),
                        ),
                        _buildFilterChip(
                          label: 'Çoktan Seçmeli ($mcCount)',
                          selected: _questionTypeFilter == 'multiple_choice',
                          onTap: () => setState(() {
                            _questionTypeFilter = 'multiple_choice';
                            _applyTypeFilterSelection();
                          }),
                        ),
                        _buildFilterChip(
                          label: 'Egzersiz Sorusu ($exCount)',
                          selected: _questionTypeFilter == 'exercise',
                          onTap: () => setState(() {
                            _questionTypeFilter = 'exercise';
                            _applyTypeFilterSelection();
                          }),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Text(
                            '🎯 ${uniqueK12Codes.length} Farklı Kazanım',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 3. Eşleştirme ve Zorluk Ayarları
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _autoSyncOutcomeLists,
                                visualDensity: VisualDensity.compact,
                                activeColor: Colors.indigo,
                                onChanged: _isImporting
                                    ? null
                                    : (v) => setState(
                                        () => _autoSyncOutcomeLists = v ?? true,
                                      ),
                              ),
                              const Text(
                                'Kazanımları Kurum Kazanım Listesine de Ekle (outcome_lists)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _tryCacheDriveImagesAsBase64,
                                visualDensity: VisualDensity.compact,
                                activeColor: Colors.teal,
                                onChanged: _isImporting
                                    ? null
                                    : (v) => setState(
                                        () => _tryCacheDriveImagesAsBase64 =
                                            v ?? true,
                                      ),
                              ),
                              const Text(
                                'Drive Görsellerini PDF İçin Önbellekle',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _syncRemoveMissing,
                                visualDensity: VisualDensity.compact,
                                activeColor: Colors.deepOrange,
                                onChanged: _isImporting
                                    ? null
                                    : (v) => setState(() => _syncRemoveMissing = v ?? false),
                              ),
                              const Text(
                                'Senkronize Et: Tablodan silinen soruları havuzdan da kaldır',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if ((_alreadyImportedCount ?? 0) > 0)
                            OutlinedButton.icon(
                              onPressed: (_isImporting || _isDeleting)
                                  ? null
                                  : _deleteAllImportedFromSheet,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: _isDeleting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.delete_sweep_rounded, size: 17),
                              label: Text(
                                'Bu Tablodan Aktarılan $_alreadyImportedCount Soruyu Toplu Sil',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // 4. Tablo Başlığı
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade900,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Checkbox(
                              value: visible.isNotEmpty &&
                                  visible.every((r) => r.selected),
                              tristate: false,
                              side: const BorderSide(color: Colors.white70),
                              activeColor: Colors.tealAccent.shade700,
                              onChanged: _isImporting
                                  ? null
                                  : (val) {
                                      setState(() {
                                        for (final r in visible) {
                                          r.selected = val ?? false;
                                        }
                                      });
                                    },
                            ),
                          ),
                          _headerCell('No', width: 42),
                          _headerCell('Görsel', width: 64),
                          _headerCell('Sınıf / Branş / Konu', flex: 2),
                          _headerCell('Gerçek Kod', width: 92),
                          _headerCell('Gerçek Kazanım Açıklaması (2026-2027)', flex: 4),
                          _headerCell('Tür', width: 105),
                          _headerCell('Zorluk', width: 96),
                          _headerCell('Cevap', width: 54),
                        ],
                      ),
                    ),

                    // 5. Önizleme Listesi
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: visible.isEmpty
                            ? const Center(
                                child: Text(
                                  'Gösterilecek soru bulunamadı.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                                itemBuilder: (ctx, idx) {
                                  final r = visible[idx];
                                  final diffLabel =
                                      DifficultyScale.labels[r.difficultyLevel - 1];
                                  final diffColor =
                                      DifficultyScale.colors[r.difficultyLevel - 1];

                                  return Container(
                                    color: r.selected
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 32,
                                          child: Checkbox(
                                            value: r.selected,
                                            visualDensity: VisualDensity.compact,
                                            onChanged: _isImporting
                                                ? null
                                                : (v) => setState(
                                                    () => r.selected = v ?? false,
                                                  ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 42,
                                          child: Text(
                                            '#${r.questionNo}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo.shade900,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 64,
                                          height: 44,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                            child: DriveImageHelper
                                                .buildPoolQuestionImage(
                                              imageUrl: r.rawImageUrl,
                                              driveFileId: r.driveFileId,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${r.classLevel} • ${r.subject}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.indigo,
                                                ),
                                              ),
                                              Text(
                                                r.topic,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: const Color(0xFF334155),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 88,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            margin:
                                                const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.teal.shade300,
                                              ),
                                            ),
                                            child: Text(
                                              r.effectiveKazanimCode.isNotEmpty
                                                  ? r.effectiveKazanimCode
                                                  : '-',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 4,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  r.effectiveOutcome,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(
                                                      0xFF1E293B,
                                                    ),
                                                  ),
                                                ),
                                                if (r.subTopic.isNotEmpty)
                                                  Text(
                                                    'Alt Konu: ${r.subTopic}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 105,
                                          child: Text(
                                            r.questionType,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: _normTr(r.questionType)
                                                      .contains('egzersiz')
                                                  ? Colors.purple.shade700
                                                  : Colors.blueGrey.shade800,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 96,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            margin:
                                                const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: diffColor.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$diffLabel (${r.rawDifficulty})',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: diffColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 54,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 3,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.indigo,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              r.correctAnswer,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── ALT İLERLEME VE AKSİYON ÇUBUĞU ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: _isImporting
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _importStatusText,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: _importTotal > 0
                                    ? (_importCurrent / _importTotal)
                                        .clamp(0.0, 1.0)
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Seçili $selectedCount soru (${uniqueK12Codes.length} farklı kazanım) Soru Havuzuna aktarılacak.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Vazgeç'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: selectedCount == 0
                              ? null
                              : _importSelectedQuestions,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.cloud_download_rounded, size: 18),
                          label: Text(
                            '$selectedCount Soruyu Havuza Aktar',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F766E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF0F766E) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, {double? width, int? flex}) {
    final child = Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    if (flex != null) {
      return Expanded(flex: flex, child: child);
    }
    return SizedBox(width: width, child: child);
  }
}
