class LgsPercentileRange {
  final double minScore;
  final double maxScore;
  final double minPercentile;
  final double maxPercentile;

  const LgsPercentileRange({
    required this.minScore,
    required this.maxScore,
    required this.minPercentile,
    required this.maxPercentile,
  });
}

/// MEB LGS Merkezi Sınav Raporları ve 1. Yerleştirme Taban Puan / Yüzdelik Dilim
/// verilerine göre kalibre edilmiş Türkiye geneli referans aralıkları:
/// - 2026 LGS: 994.358 katılımcı, 452 tam puan (Matematik seçici; 450-485 bandı 2025'e göre ~2-5 puan daha düşük kapattı)
/// - 2025 LGS: 963.142 katılımcı, 719 tam puan (Üst dilimde puan yığılması daha yüksek)
/// - 2024 LGS: 992.906 katılımcı, 352 tam puan
const Map<String, List<LgsPercentileRange>> lgsPercentiles = {
  "2026": [
    LgsPercentileRange(
      minScore: 495,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.08,
    ),
    LgsPercentileRange(
      minScore: 490,
      maxScore: 495,
      minPercentile: 0.08,
      maxPercentile: 0.21,
    ),
    LgsPercentileRange(
      minScore: 485,
      maxScore: 490,
      minPercentile: 0.21,
      maxPercentile: 0.42,
    ),
    LgsPercentileRange(
      minScore: 475,
      maxScore: 485,
      minPercentile: 0.42,
      maxPercentile: 0.96,
    ),
    LgsPercentileRange(
      minScore: 465,
      maxScore: 475,
      minPercentile: 0.96,
      maxPercentile: 1.75,
    ),
    LgsPercentileRange(
      minScore: 450,
      maxScore: 465,
      minPercentile: 1.75,
      maxPercentile: 3.10,
    ),
    LgsPercentileRange(
      minScore: 435,
      maxScore: 450,
      minPercentile: 3.10,
      maxPercentile: 5.40,
    ),
    LgsPercentileRange(
      minScore: 415,
      maxScore: 435,
      minPercentile: 5.40,
      maxPercentile: 9.20,
    ),
    LgsPercentileRange(
      minScore: 390,
      maxScore: 415,
      minPercentile: 9.20,
      maxPercentile: 15.20,
    ),
    LgsPercentileRange(
      minScore: 360,
      maxScore: 390,
      minPercentile: 15.20,
      maxPercentile: 24.50,
    ),
    LgsPercentileRange(
      minScore: 330,
      maxScore: 360,
      minPercentile: 24.50,
      maxPercentile: 36.50,
    ),
    LgsPercentileRange(
      minScore: 290,
      maxScore: 330,
      minPercentile: 36.50,
      maxPercentile: 53.00,
    ),
    LgsPercentileRange(
      minScore: 240,
      maxScore: 290,
      minPercentile: 53.00,
      maxPercentile: 73.00,
    ),
    LgsPercentileRange(
      minScore: 200,
      maxScore: 240,
      minPercentile: 73.00,
      maxPercentile: 88.00,
    ),
  ],
  "2025": [
    LgsPercentileRange(
      minScore: 495,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.09,
    ),
    LgsPercentileRange(
      minScore: 490,
      maxScore: 495,
      minPercentile: 0.09,
      maxPercentile: 0.28,
    ),
    LgsPercentileRange(
      minScore: 485,
      maxScore: 490,
      minPercentile: 0.28,
      maxPercentile: 0.56,
    ),
    LgsPercentileRange(
      minScore: 475,
      maxScore: 485,
      minPercentile: 0.56,
      maxPercentile: 1.22,
    ),
    LgsPercentileRange(
      minScore: 465,
      maxScore: 475,
      minPercentile: 1.22,
      maxPercentile: 2.05,
    ),
    LgsPercentileRange(
      minScore: 450,
      maxScore: 465,
      minPercentile: 2.05,
      maxPercentile: 3.65,
    ),
    LgsPercentileRange(
      minScore: 435,
      maxScore: 450,
      minPercentile: 3.65,
      maxPercentile: 6.10,
    ),
    LgsPercentileRange(
      minScore: 415,
      maxScore: 435,
      minPercentile: 6.10,
      maxPercentile: 10.20,
    ),
    LgsPercentileRange(
      minScore: 390,
      maxScore: 415,
      minPercentile: 10.20,
      maxPercentile: 16.50,
    ),
    LgsPercentileRange(
      minScore: 360,
      maxScore: 390,
      minPercentile: 16.50,
      maxPercentile: 26.00,
    ),
    LgsPercentileRange(
      minScore: 330,
      maxScore: 360,
      minPercentile: 26.00,
      maxPercentile: 38.00,
    ),
    LgsPercentileRange(
      minScore: 290,
      maxScore: 330,
      minPercentile: 38.00,
      maxPercentile: 55.00,
    ),
    LgsPercentileRange(
      minScore: 240,
      maxScore: 290,
      minPercentile: 55.00,
      maxPercentile: 74.50,
    ),
    LgsPercentileRange(
      minScore: 200,
      maxScore: 240,
      minPercentile: 74.50,
      maxPercentile: 89.00,
    ),
  ],
  "2024": [
    LgsPercentileRange(
      minScore: 495,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.06,
    ),
    LgsPercentileRange(
      minScore: 490,
      maxScore: 495,
      minPercentile: 0.06,
      maxPercentile: 0.20,
    ),
    LgsPercentileRange(
      minScore: 485,
      maxScore: 490,
      minPercentile: 0.20,
      maxPercentile: 0.45,
    ),
    LgsPercentileRange(
      minScore: 475,
      maxScore: 485,
      minPercentile: 0.45,
      maxPercentile: 1.20,
    ),
    LgsPercentileRange(
      minScore: 465,
      maxScore: 475,
      minPercentile: 1.20,
      maxPercentile: 2.25,
    ),
    LgsPercentileRange(
      minScore: 450,
      maxScore: 465,
      minPercentile: 2.25,
      maxPercentile: 4.10,
    ),
    LgsPercentileRange(
      minScore: 435,
      maxScore: 450,
      minPercentile: 4.10,
      maxPercentile: 6.80,
    ),
    LgsPercentileRange(
      minScore: 415,
      maxScore: 435,
      minPercentile: 6.80,
      maxPercentile: 11.00,
    ),
    LgsPercentileRange(
      minScore: 390,
      maxScore: 415,
      minPercentile: 11.00,
      maxPercentile: 17.50,
    ),
    LgsPercentileRange(
      minScore: 360,
      maxScore: 390,
      minPercentile: 17.50,
      maxPercentile: 27.50,
    ),
    LgsPercentileRange(
      minScore: 330,
      maxScore: 360,
      minPercentile: 27.50,
      maxPercentile: 40.00,
    ),
    LgsPercentileRange(
      minScore: 290,
      maxScore: 330,
      minPercentile: 40.00,
      maxPercentile: 57.00,
    ),
    LgsPercentileRange(
      minScore: 240,
      maxScore: 290,
      minPercentile: 57.00,
      maxPercentile: 76.00,
    ),
    LgsPercentileRange(
      minScore: 200,
      maxScore: 240,
      minPercentile: 76.00,
      maxPercentile: 90.00,
    ),
  ],
};

String getLgsPercentile(double score, String year) {
  final ranges = lgsPercentiles[year] ?? lgsPercentiles["2026"];
  if (ranges == null) return "-";

  if (score >= 500) return "%0.01";
  if (score < 200) return ">%90.00";

  for (var range in ranges) {
    if (score >= range.minScore && score <= range.maxScore) {
      double scoreRange = range.maxScore - range.minScore;
      if (scoreRange == 0) return "%${range.minPercentile.toStringAsFixed(2)}";

      double scoreFraction = (score - range.minScore) / scoreRange;
      double percentileRange = range.maxPercentile - range.minPercentile;

      // Higher score -> Lower percentile (better rank)
      double estimatedPercentile =
          range.maxPercentile - (scoreFraction * percentileRange);

      return "%${estimatedPercentile.toStringAsFixed(2)}";
    }
  }

  return "-";
}

String getLgsPercentileRangeString(double score, String year) {
  final ranges = lgsPercentiles[year] ?? lgsPercentiles["2026"];
  if (ranges == null) return "-";

  if (score >= 500) {
    final top = ranges.first;
    return "%${top.minPercentile.toStringAsFixed(2)} - %${top.maxPercentile.toStringAsFixed(2)}";
  }
  if (score < 200) {
    return "%90.00+";
  }

  for (var range in ranges) {
    if (score >= range.minScore && score <= range.maxScore) {
      return "%${range.minPercentile.toStringAsFixed(2)} - %${range.maxPercentile.toStringAsFixed(2)}";
    }
  }
  return "-";
}

