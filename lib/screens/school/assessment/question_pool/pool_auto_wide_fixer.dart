import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../models/assessment/outcome_list_model.dart';
import '../../../../utils/drive_image_helper.dart';
import '../../../../utils/difficulty_scale.dart';
import '../../../../utils/gercek_kazanim_mapper.dart';
import 'google_sheets_seed_data.dart';

/// Google Tablodan aktarılmış (`sourceType == 'google_sheets'`) soruların görsel
/// piksel genişliğini ölçüp `isWide` (1 / 2 Sütun) alanını arka planda düzeltir.
/// Ayrıca tüm havuz sorularını (Tablo + Hata Kitapçığı/Deneme Sınavı) ve `outcome_lists`
/// kayıtlarını 2026-2027 TYMM "Gerçek Kazanım Kodu ve Açıklaması" yapısına dönüştürür.
class PoolAutoWideFixer {
  static final Set<String> _processed = {};
  static bool _running = false;

  static bool _needsCheck(Map<String, dynamic> d) =>
      d['sourceType'] == 'google_sheets' &&
      d['isWideManual'] != true &&
      d['autoWideVersion'] != DriveImageHelper.kAutoWideVersion;

  static void schedule(
    List<Map<String, dynamic>> docs, {
    List<Map<String, dynamic>>? visibleDocs,
    VoidCallback? onChanged,
  }) {
    _scheduleDifficultyMigration(docs);
    _scheduleGercekKazanimMigration(docs);
    if (_running) return;
    // Yalnızca ekranda o an görünen (veya ilk 8) sorunun görsel boyutunu kontrol et;
    // tüm havuzdaki yüzlerce görseli aynı anda indirip arayüzü dondurma!
    final targetDocs = visibleDocs ?? (docs.length > 8 ? docs.sublist(0, 8) : docs);
    final pending = targetDocs.where((d) {
      if (!_needsCheck(d)) return false;
      return !_processed.contains('${d['examId']}/${d['docId']}');
    }).toList();
    if (pending.isEmpty) return;

    _running = true;
    Future(() async {
      try {
        const chunk = 4;
        for (int i = 0; i < pending.length; i += chunk) {
          final slice = pending.sublist(
            i,
            i + chunk > pending.length ? pending.length : i + chunk,
          );
          final results = await Future.wait(slice.map(_fixOne));
          if (results.any((changed) => changed)) onChanged?.call();
        }
      } catch (e) {
        debugPrint('[PoolAutoWideFixer] $e');
      } finally {
        _running = false;
      }
    });
  }

  /// Returns true if the local map's `isWide` changed.
  static Future<bool> _fixOne(Map<String, dynamic> d) async {
    final examId = d['examId']?.toString();
    final docId = d['docId']?.toString();
    if (examId == null || docId == null) return false;
    _processed.add('$examId/$docId');

    final size = await DriveImageHelper.getImageSize(
      base64Image: d['base64Image']?.toString(),
      imageUrl: d['imageUrl']?.toString(),
      driveFileId: d['driveFileId']?.toString(),
    );
    if (size == null) return false;

    final bool wide = DriveImageHelper.shouldBeWide(size);
    final bool changed = (d['isWide'] == true) != wide;
    d['isWide'] = wide;
    d['imageWidth'] = size.width;
    d['imageHeight'] = size.height;
    d['autoWideVersion'] = DriveImageHelper.kAutoWideVersion;

    try {
      await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(examId)
          .collection('questions_pool')
          .doc(docId)
          .update({
        'isWide': wide,
        'imageWidth': size.width,
        'imageHeight': size.height,
        'autoWideChecked': true,
        'autoWideVersion': DriveImageHelper.kAutoWideVersion,
      });
    } catch (e) {
      debugPrint('[PoolAutoWideFixer] update failed $docId: $e');
    }
    return changed;
  }

  /// Tablodan aktarılan soruların zorluğunu tablodaki 1–5 seviyesine göre
  /// 5 aşamalı ölçeğe (Hata Kitapçığı ile aynı) dönüştürür. Elle değiştirilen zorluklara dokunmaz.
  static final Set<String> _diffProcessed = {};

  static void _scheduleDifficultyMigration(
    List<Map<String, dynamic>> docs, {
    VoidCallback? onChanged,
  }) {
    final pending = docs.where((d) {
      if (d['sourceType'] != 'google_sheets') return false;
      if (d['difficultyManual'] == true) return false;
      if (d['difficultyScaleVersion'] == 2) return false;
      final key = '${d['examId']}/${d['docId']}';
      return !_diffProcessed.contains(key);
    }).toList();
    if (pending.isEmpty) return;

    Future(() async {
      bool anyChanged = false;
      for (int i = 0; i < pending.length; i += 400) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in pending.sublist(i, i + 400 > pending.length ? pending.length : i + 400)) {
          final examId = d['examId']?.toString();
          final docId = d['docId']?.toString();
          if (examId == null || docId == null) continue;
          _diffProcessed.add('$examId/$docId');
          final lvl = int.tryParse(
                (d['rawDifficultyLevel'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              3;
          final level = lvl.clamp(1, 5);
          final score = DifficultyScale.scoreForLevel(level);
          d['difficulty'] = score;
          d['difficultyLevel'] = level;
          d['difficultyScaleVersion'] = 2;
          anyChanged = true;
          batch.update(
            FirebaseFirestore.instance
                .collection('trial_exams')
                .doc(examId)
                .collection('questions_pool')
                .doc(docId),
            {'difficulty': score, 'difficultyLevel': level, 'difficultyScaleVersion': 2},
          );
        }
        try {
          await batch.commit();
        } catch (e) {
          debugPrint('[PoolAutoWideFixer] difficulty migration failed: $e');
        }
      }
      if (anyChanged) onChanged?.call();
    });
  }

  // ─── 2026-2027 TYMM "Gerçek Kazanım" Otomatik Dönüşümü (Tablo + Hata Kitapçığı) ───

  static final Set<String> _kazanimProcessed = {};
  static Map<
          String,
          Map<int, ({String topic, String code, String text, String sub, String legacy})>>?
      _sheetRowsBySheetIdCache;

  static Map<
          String,
          Map<int, ({String topic, String code, String text, String sub, String legacy})>>
      get _sheetRowsBySheetId {
    if (_sheetRowsBySheetIdCache != null) return _sheetRowsBySheetIdCache!;
    final result = <String,
        Map<int, ({String topic, String code, String text, String sub, String legacy})>>{};
    for (final entry in kBuiltInQuestionPoolSheetsById.entries) {
      final sheetId = entry.key;
      final rows = entry.value;
      final map = <int, ({String topic, String code, String text, String sub, String legacy})>{};
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 7) continue;
        final qNo = int.tryParse(row[0].trim()) ?? i;
        final rowTopic = row[3].trim();
        final rawCode = row[4].trim();
        final rawDesc = row[5].trim();
        final rawK12 = row[6].trim();
        final split = GercekKazanimMapper.splitOutcomeTextAndSubTopic(
          rawDesc,
          explicitCode: rawCode,
        );
        GercekKazanimMapper.registerFromSheetRow(
          gercekCode: split.code,
          gercekBaseText: split.text,
          k12MappingCell: rawK12,
          topic: rowTopic,
        );
        map[qNo] = (
          topic: rowTopic,
          code: split.code,
          text: split.text,
          sub: split.sub,
          legacy: rawK12,
        );
      }
      result[sheetId] = map;
    }
    _sheetRowsBySheetIdCache = result;
    return result;
  }

  static String? _resolveKnownSheetIdForDoc(Map<String, dynamic> d) {
    final rawSheetId = (d['sourceSheetId'] ?? '').toString().trim();
    if (rawSheetId.isNotEmpty && kBuiltInQuestionPoolSheetsById.containsKey(rawSheetId)) {
      return rawSheetId;
    }
    final docId = (d['docId'] ?? '').toString().trim();
    for (final knownId in kBuiltInQuestionPoolSheetsById.keys) {
      final shortId = knownId.length > 10 ? knownId.substring(0, 10) : knownId;
      if (docId.startsWith('sheet_${shortId}_')) {
        return knownId;
      }
    }
    final fileName = (d['fileName'] ?? '').toString();
    if (fileName.contains('_CumledeAnlam_')) {
      return kCumledeAnlamQuestionPoolSheetId;
    }
    if (fileName.contains('_SozcukteAnlam_')) {
      return kDefaultQuestionPoolSheetId;
    }
    return null;
  }

  static void _scheduleGercekKazanimMigration(
    List<Map<String, dynamic>> docs, {
    VoidCallback? onChanged,
  }) {
    // Önce yerel haritaları senkron güncelle (ekranda anında Gerçek Kazanım ve doğru Konu görünsün)
    final allSheetsMap = _sheetRowsBySheetId;
    final List<({Map<String, dynamic> doc, Map<String, dynamic> updates})>
        pendingUpdates = [];

    for (final d in docs) {
      if (d['_kazanimMigratedMem'] == true) continue;
      d['_kazanimMigratedMem'] = true;

      final examId = d['examId']?.toString();
      final docId = d['docId']?.toString();
      final key = '$examId/$docId';

      final bool isSheet = d['sourceType'] == 'google_sheets';
      final int qNo = (num.tryParse('${d['questionNo']}') ?? 0).toInt();

      String newTopic = (d['topic'] ?? '').toString().trim();
      String newCode = (d['kazanimCode'] ?? '').toString().trim();
      String newOutcome = (d['outcome'] ?? '').toString().trim();
      String newSubTopic = (d['subTopic'] ?? '').toString().trim();
      bool shouldUpdate = false;

      final knownSheetId = isSheet ? _resolveKnownSheetIdForDoc(d) : null;
      final sheetMap = knownSheetId != null ? allSheetsMap[knownSheetId] : null;
      final String subjNorm = GercekKazanimMapper.normTr((d['subject'] ?? '').toString());

      if (sheetMap != null &&
          sheetMap.containsKey(qNo) &&
          subjNorm.contains('turkce')) {
        final s = sheetMap[qNo]!;
        final bool sameTopicOrEmpty = newTopic.isEmpty ||
            GercekKazanimMapper.normTr(newTopic) == GercekKazanimMapper.normTr(s.topic);
        if (sameTopicOrEmpty &&
            (newTopic != s.topic ||
                newCode != s.code ||
                newOutcome != s.text ||
                newSubTopic != s.sub ||
                d['k12Code'] != null ||
                d['gercekKazanimVersion'] != 3)) {
          newTopic = s.topic;
          newCode = s.code;
          newOutcome = s.text;
          newSubTopic = s.sub;
          shouldUpdate = true;
        }
      } else {
        final resolved = GercekKazanimMapper.resolve(
          rawCode: newCode,
          rawOutcome: newOutcome,
          k12Code: d['k12Code']?.toString(),
          legacyOutcome: d['legacyOutcome']?.toString(),
          existingSubTopic: newSubTopic,
        );
        if (resolved.code.isNotEmpty &&
            (newCode != resolved.code ||
                newOutcome != resolved.description ||
                d['k12Code'] != null)) {
          newCode = resolved.code;
          newOutcome = resolved.description;
          if (newSubTopic.isEmpty && resolved.subTopic.isNotEmpty) {
            newSubTopic = resolved.subTopic;
          }
          shouldUpdate = true;
        } else if (d['k12Code'] != null) {
          shouldUpdate = true;
        }
      }

      if (shouldUpdate) {
        if (newTopic.isNotEmpty) {
          d['topic'] = newTopic;
        }
        d['kazanimCode'] = newCode;
        d['outcome'] = newOutcome;
        d['subTopic'] = newSubTopic;
        d.remove('k12Code');
        d.remove('k12OutcomeFull');
        d['gercekKazanimVersion'] = 3;

        if (examId != null &&
            docId != null &&
            !_kazanimProcessed.contains(key)) {
          _kazanimProcessed.add(key);
          pendingUpdates.add((
            doc: d,
            updates: {
              if (newTopic.isNotEmpty) 'topic': newTopic,
              'kazanimCode': newCode,
              'outcome': newOutcome,
              'subTopic': newSubTopic,
              'k12Code': FieldValue.delete(),
              'k12OutcomeFull': FieldValue.delete(),
              'gercekKazanimVersion': 3,
            },
          ));
        }
      }
    }

    if (pendingUpdates.isEmpty) return;

    Future(() async {
      for (int i = 0; i < pendingUpdates.length; i += 400) {
        final batch = FirebaseFirestore.instance.batch();
        final slice = pendingUpdates.sublist(
          i,
          i + 400 > pendingUpdates.length ? pendingUpdates.length : i + 400,
        );
        for (final item in slice) {
          final examId = item.doc['examId']?.toString();
          final docId = item.doc['docId']?.toString();
          if (examId == null || docId == null) continue;
          batch.update(
            FirebaseFirestore.instance
                .collection('trial_exams')
                .doc(examId)
                .collection('questions_pool')
                .doc(docId),
            item.updates,
          );
        }
        try {
          await batch.commit();
        } catch (e) {
          debugPrint('[PoolAutoWideFixer] gercekKazanim migration failed: $e');
        }
      }
      onChanged?.call();
    });
  }

  /// Kurumun `outcome_lists` kayıtlarındaki eski K12 taslak kodlarını (`T.O.7.1.20` vb.)
  /// ve yazım hatalarını (`yapa bilme` vb.) Gerçek Kazanım Kodu ve Açıklamasına dönüştürür,
  /// ayrıca her Konu (`Sözcükte Anlam`, `Cümlede Anlam` vb.) başlığının kendi alt kazanımlarının
  /// eksiksiz bulunmasını sağlar.
  static final Set<String> _migratedOutcomeListIds = {};

  static void scheduleOutcomeListsMigration(List<OutcomeList> lists) {
    final allSheets = _sheetRowsBySheetId;

    for (final ol in lists) {
      if (ol.id.isEmpty || _migratedOutcomeListIds.contains(ol.id)) continue;
      bool changed = false;
      final List<OutcomeItem> updatedItems = [];
      final Set<String> seenInTopic = {};

      for (final item in ol.outcomes) {
        if (item.depth == 1) {
          seenInTopic.clear();
          updatedItems.add(item);
          continue;
        }
        final resolved = GercekKazanimMapper.resolve(
          rawCode: item.code,
          rawOutcome: item.description,
          k12Code: item.k12Code,
        );
        final String newCode =
            resolved.code.isNotEmpty ? resolved.code : item.code.trim();
        final String newDesc = resolved.description.isNotEmpty
            ? resolved.description
            : item.description.trim();

        if (item.code != newCode ||
            item.description != newDesc ||
            item.k12Code.isNotEmpty) {
          changed = true;
        }

        final dedupKey =
            '${GercekKazanimMapper.normAlnum(newCode)}_${GercekKazanimMapper.normAlnum(newDesc)}';
        if (seenInTopic.add(dedupKey)) {
          updatedItems.add(
            OutcomeItem(
              code: newCode,
              description: newDesc,
              depth: item.depth,
              k12Code: '',
            ),
          );
        } else {
          changed = true;
        }
      }

      // 7. Sınıf Türkçe için tablolardaki tüm Konu ("Sözcükte Anlam", "Cümlede Anlam" vb.)
      // başlıklarının kendi alt kazanımlarının o konu başlığı altında eksiksiz yer almasını sağla
      final normCls = GercekKazanimMapper.normTr(ol.classLevel);
      final normBranch = GercekKazanimMapper.normTr(ol.branchName);
      if (normCls.contains('7') && normBranch.contains('turkce')) {
        for (final sheetMap in allSheets.values) {
          if (sheetMap.isEmpty) continue;
          final String topicName = sheetMap.values.first.topic.trim();
          if (topicName.isEmpty) continue;

          int topicIdx = updatedItems.indexWhere(
            (i) =>
                i.depth == 1 &&
                GercekKazanimMapper.normTr(i.description) ==
                    GercekKazanimMapper.normTr(topicName),
          );
          if (topicIdx == -1) {
            updatedItems.add(
              OutcomeItem(
                code: '',
                description: topicName,
                depth: 1,
                k12Code: '',
              ),
            );
            topicIdx = updatedItems.length - 1;
            changed = true;
          }

          for (final row in sheetMap.values) {
            if (row.text.isEmpty) continue;
            int topicEndIdx = topicIdx + 1;
            while (topicEndIdx < updatedItems.length &&
                updatedItems[topicEndIdx].depth != 1) {
              topicEndIdx++;
            }
            bool existsInThisTopic = false;
            for (int idx = topicIdx + 1; idx < topicEndIdx; idx++) {
              final cur = updatedItems[idx];
              if ((row.code.isNotEmpty &&
                      GercekKazanimMapper.normAlnum(cur.code) ==
                          GercekKazanimMapper.normAlnum(row.code)) ||
                  GercekKazanimMapper.normAlnum(cur.description) ==
                      GercekKazanimMapper.normAlnum(row.text)) {
                existsInThisTopic = true;
                break;
              }
            }
            if (!existsInThisTopic) {
              updatedItems.insert(
                topicEndIdx,
                OutcomeItem(
                  code: row.code,
                  description: row.text,
                  depth: 2,
                  k12Code: '',
                ),
              );
              changed = true;
            }
          }
        }
      }

      _migratedOutcomeListIds.add(ol.id);
      if (changed) {
        ol.outcomes
          ..clear()
          ..addAll(updatedItems);
        FirebaseFirestore.instance
            .collection('outcome_lists')
            .doc(ol.id)
            .update({
              'outcomes': updatedItems.map((e) => e.toMap()).toList(),
            })
            .catchError((e) {
              debugPrint('[PoolAutoWideFixer] outcome_lists update error: $e');
            });
      }
    }
  }

  /// Tek tıkla 1 ⇄ 2 Sütun değiştirir (elle karar olarak işaretlenir, otomatik düzeltme bir daha dokunmaz).
  static Future<void> toggleWideManually(Map<String, dynamic> d) async {
    final examId = d['examId']?.toString();
    final docId = d['docId']?.toString();
    if (examId == null || docId == null) return;
    final bool newWide = d['isWide'] != true;
    d['isWide'] = newWide;
    d['isWideManual'] = true;
    await FirebaseFirestore.instance
        .collection('trial_exams')
        .doc(examId)
        .collection('questions_pool')
        .doc(docId)
        .update({
      'isWide': newWide,
      'isWideManual': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
