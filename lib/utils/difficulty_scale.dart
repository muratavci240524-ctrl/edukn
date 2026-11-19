import 'package:flutter/material.dart';

/// Hata Kitapçığı, Soru Havuzu ve Fokus Kitap'ta ortak kullanılan 5 aşamalı zorluk ölçeği.
///
/// `difficulty` alanı 0–100 arası "başarı yüzdesi"dir (yüksek = kolay):
///   0–20  → Çok Zor   (seviye 5)
///   21–40 → Zor       (seviye 4)
///   41–60 → Orta      (seviye 3)
///   61–80 → Kolay     (seviye 2)
///   81–100→ Çok Kolay (seviye 1)
class DifficultyScale {
  /// Kolaydan zora sıralı etiketler (indeks 0 = Seviye 1 = Çok Kolay).
  static const List<String> labels = ['Çok Kolay', 'Kolay', 'Orta', 'Zor', 'Çok Zor'];
  static const List<String> levels = labels;

  static const List<Color> colors = [
    Color(0xFF2E7D32), // Çok Kolay - koyu yeşil
    Color(0xFF7CB342), // Kolay - açık yeşil
    Color(0xFFF9A825), // Orta - amber
    Color(0xFFEF6C00), // Zor - turuncu
    Color(0xFFC62828), // Çok Zor - kırmızı
  ];

  /// Her seviyenin havuza kaydedilen temsilî başarı yüzdesi (bandın ortası).
  static const List<double> representativeScores = [90, 70, 50, 30, 10];

  /// Başarı yüzdesinden seviye (1 = Çok Kolay … 5 = Çok Zor).
  static int levelOf(double successPct) {
    if (successPct <= 20) return 5;
    if (successPct <= 40) return 4;
    if (successPct <= 60) return 3;
    if (successPct <= 80) return 2;
    return 1;
  }

  static String labelOf(double successPct) => labels[levelOf(successPct) - 1];

  static Color colorOf(double successPct) => colors[levelOf(successPct) - 1];

  /// Tablo/elle girilen 1–5 seviyesini havuz `difficulty` değerine çevirir.
  static double scoreForLevel(int level) =>
      representativeScores[level.clamp(1, 5) - 1];

  /// Etiketten seviye (bulunamazsa 3 = Orta).
  static int levelOfLabel(String label) {
    final i = labels.indexOf(label);
    return i == -1 ? 3 : i + 1;
  }

  /// Etiketten renk döner.
  static Color colorForLabel(String label) => colors[levelOfLabel(label) - 1];

  /// Etiketten temsilî başarı yüzdesi döner.
  static double scoreForLabel(String label) =>
      scoreForLevel(levelOfLabel(label));

  /// Zorluk değeri olmayan sorular için varsayılan (Orta).
  static const double defaultScore = 50;
}

