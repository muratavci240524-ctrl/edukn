import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// Tüm alan (modül) demo üreticilerinin kayıt defteri.
/// Ana üretici ([DemoDataSeeder]) bu sınıf üzerinden ek modülleri çalıştırır.
class DemoSeedRegistry {
  DemoSeedRegistry._();

  /// Her alan üreticisi: (ad, çalıştırıcı).
  static final List<MapEntry<String, Future<void> Function(DemoSeedContext)>>
  seeders = [];

  /// Üst düzey koleksiyonlar (institutionId + isDemo ile temizlenir).
  static final List<String> topCollections = [];

  /// `schools/{schoolDocId}/<ad>` alt koleksiyonları (isDemo ile temizlenir).
  static final List<String> schoolSubcollections = [];

  /// Ek (iç içe) temizlik fonksiyonları: silinen doküman sayısını döner.
  static final List<
    Future<int> Function(
      FirebaseFirestore db,
      String inst,
      String prefix,
      String schoolDocId,
    )
  >
  extraCleaners = [];

  static Future<void> seedAll(
    DemoSeedContext ctx, {
    void Function(String message)? onStep,
  }) async {
    for (final e in seeders) {
      onStep?.call(e.key);
      try {
        await e.value(ctx);
        await ctx.w.flush();
      } catch (err) {
        // Bir alandaki hata diğer alanları durdurmasın.
        ctx.counts['⚠ ${e.key} (hata)'] = 1;
        // ignore: avoid_print
        print('[DemoSeed] ${e.key} hata: $err');
      }
    }
  }
}
