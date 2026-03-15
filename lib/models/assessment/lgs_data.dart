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

const Map<String, List<LgsPercentileRange>> lgsPercentiles = {
  "2025": [
    LgsPercentileRange(
      minScore: 495,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.05,
    ),
    LgsPercentileRange(
      minScore: 485,
      maxScore: 494.99,
      minPercentile: 0.06,
      maxPercentile: 0.35,
    ),
    LgsPercentileRange(
      minScore: 470,
      maxScore: 484.99,
      minPercentile: 0.36,
      maxPercentile: 1.20,
    ),
    LgsPercentileRange(
      minScore: 450,
      maxScore: 469.99,
      minPercentile: 1.21,
      maxPercentile: 3.50,
    ),
    LgsPercentileRange(
      minScore: 430,
      maxScore: 449.99,
      minPercentile: 3.51,
      maxPercentile: 7.00,
    ),
    LgsPercentileRange(
      minScore: 400,
      maxScore: 429.99,
      minPercentile: 7.01,
      maxPercentile: 12.50,
    ),
    LgsPercentileRange(
      minScore: 350,
      maxScore: 399.99,
      minPercentile: 12.51,
      maxPercentile: 25.00,
    ),
    LgsPercentileRange(
      minScore: 300,
      maxScore: 349.99,
      minPercentile: 25.01,
      maxPercentile: 45.00,
    ),
    LgsPercentileRange(
      minScore: 200,
      maxScore: 299.99,
      minPercentile: 45.01,
      maxPercentile: 85.00,
    ),
  ],
  "2024": [
    LgsPercentileRange(
      minScore: 490,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.15,
    ),
    LgsPercentileRange(
      minScore: 475,
      maxScore: 489.99,
      minPercentile: 0.16,
      maxPercentile: 0.85,
    ),
    LgsPercentileRange(
      minScore: 455,
      maxScore: 474.99,
      minPercentile: 0.86,
      maxPercentile: 2.80,
    ),
    LgsPercentileRange(
      minScore: 435,
      maxScore: 454.99,
      minPercentile: 2.81,
      maxPercentile: 5.50,
    ),
    LgsPercentileRange(
      minScore: 415,
      maxScore: 434.99,
      minPercentile: 5.51,
      maxPercentile: 9.00,
    ),
    LgsPercentileRange(
      minScore: 380,
      maxScore: 414.99,
      minPercentile: 9.01,
      maxPercentile: 16.00,
    ),
    LgsPercentileRange(
      minScore: 330,
      maxScore: 379.99,
      minPercentile: 16.01,
      maxPercentile: 32.00,
    ),
    LgsPercentileRange(
      minScore: 250,
      maxScore: 329.99,
      minPercentile: 32.01,
      maxPercentile: 65.00,
    ),
  ],
  "2023": [
    LgsPercentileRange(
      minScore: 495,
      maxScore: 500,
      minPercentile: 0.01,
      maxPercentile: 0.40,
    ),
    LgsPercentileRange(
      minScore: 485,
      maxScore: 494.99,
      minPercentile: 0.41,
      maxPercentile: 1.50,
    ),
    LgsPercentileRange(
      minScore: 470,
      maxScore: 484.99,
      minPercentile: 1.51,
      maxPercentile: 3.80,
    ),
    LgsPercentileRange(
      minScore: 450,
      maxScore: 469.99,
      minPercentile: 3.81,
      maxPercentile: 8.20,
    ),
    LgsPercentileRange(
      minScore: 430,
      maxScore: 449.99,
      minPercentile: 8.21,
      maxPercentile: 14.50,
    ),
    LgsPercentileRange(
      minScore: 400,
      maxScore: 429.99,
      minPercentile: 14.51,
      maxPercentile: 22.00,
    ),
    LgsPercentileRange(
      minScore: 350,
      maxScore: 399.99,
      minPercentile: 22.01,
      maxPercentile: 38.00,
    ),
    LgsPercentileRange(
      minScore: 250,
      maxScore: 349.99,
      minPercentile: 38.01,
      maxPercentile: 72.00,
    ),
  ],
};

String getLgsPercentile(double score, String year) {
  final ranges = lgsPercentiles[year];
  if (ranges == null) return "-";

  for (var range in ranges) {
    if (score >= range.minScore && score <= range.maxScore) {
      // Linear interpolation within the range
      // Higher score -> Lower percentile (better rank)
      // range.minScore maps to range.maxPercentile
      // range.maxScore maps to range.minPercentile

      double scoreRange = range.maxScore - range.minScore;
      if (scoreRange == 0) return range.minPercentile.toStringAsFixed(2);

      double scoreFraction = (score - range.minScore) / scoreRange;
      double percentileRange = range.maxPercentile - range.minPercentile;

      // Since higher score = lower percentile:
      double estimatedPercentile =
          range.maxPercentile - (scoreFraction * percentileRange);

      return "%${estimatedPercentile.toStringAsFixed(2)}";
    }
  }

  if (score > 500) return "%0.01"; // Should not happen ideally
  if (score < 200) return ">%85.00"; // Below tracked ranges

  return "-";
}

String getLgsPercentileRangeString(double score, String year) {
  final ranges = lgsPercentiles[year];
  if (ranges == null) return "-";

  for (var range in ranges) {
    if (score >= range.minScore && score <= range.maxScore) {
      return "%${range.minPercentile} - %${range.maxPercentile}";
    }
  }
  return "-";
}
