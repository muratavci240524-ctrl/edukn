import 'dart:math' as math;

/// ÖSYM "Sınav Puanlarının Yığılmalı Dağılımı" tablolarından alınan referans
/// noktaları (puan -> o puan ve üzerindeki aday sayısı).
///
/// Kaynak: ÖSYM 2023-YKS, 2024-YKS ve 2025-YKS sayısal bilgiler / yığılmalı dağılım
/// tabloları (TYT, SAY, EA, SÖZ ham sınav puanı; OBP eklenmemiş).
///
/// ÖNEMLİ: Tablo noktaları arasındaki değerler logaritmik doğrusal ara değerlemeyle
/// (log-lineer interpolasyon) hesaplanır; bu nedenle sonuçlar KESİN DEĞİL,
/// "tahmini referans" değerleridir. `estimated: true` olan noktalar komşu yıl
/// oranlarından türetilmiş tahminlerdir (ör. 450 puan eşiği).
class YksRankPoint {
  final double score;
  final int cumulative; // bu puan ve üzerindeki aday sayısı
  final bool estimated;
  const YksRankPoint(this.score, this.cumulative, {this.estimated = false});
}

class YksTrackData {
  /// Puanı hesaplanan toplam aday sayısı (bilinmiyorsa 200+ puanlı aday sayısı).
  final int total;

  /// `total` gerçek toplam değil, 200 ve üzeri puanlı aday sayısıysa true.
  final bool totalIsLowerBound;

  /// Puana göre AZALAN sırada referans noktaları.
  final List<YksRankPoint> points;
  const YksTrackData({
    required this.total,
    required this.points,
    this.totalIsLowerBound = false,
  });
}

/// yıl -> puan türü (TYT / SAY / EA / SOZ) -> veri
const Map<String, Map<String, YksTrackData>> yksRankData = {
  '2025': {
    'TYT': YksTrackData(
      total: 2310579,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 4860, estimated: true),
        YksRankPoint(400, 44193),
        YksRankPoint(300, 404024),
        YksRankPoint(200, 1686626),
      ],
    ),
    'SAY': YksTrackData(
      total: 1291531,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 5680, estimated: true),
        YksRankPoint(400, 40857),
        YksRankPoint(300, 169418),
        YksRankPoint(200, 627659),
      ],
    ),
    'EA': YksTrackData(
      total: 1494612,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 183, estimated: true),
        YksRankPoint(400, 2823),
        YksRankPoint(300, 115961),
        YksRankPoint(200, 875112),
      ],
    ),
    'SOZ': YksTrackData(
      total: 1174047,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 25, estimated: true),
        YksRankPoint(400, 652),
        YksRankPoint(300, 60680),
        YksRankPoint(200, 723293),
      ],
    ),
  },
  '2024': {
    'TYT': YksTrackData(
      total: 1825318,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1),
        YksRankPoint(450, 8234),
        YksRankPoint(400, 74365),
        YksRankPoint(350, 216563),
        YksRankPoint(300, 417417),
        YksRankPoint(200, 1825318),
      ],
    ),
    'SAY': YksTrackData(
      total: 549385,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1),
        YksRankPoint(450, 4750),
        YksRankPoint(400, 34156),
        YksRankPoint(350, 88385),
        YksRankPoint(300, 142684),
        YksRankPoint(200, 549385),
      ],
    ),
    'EA': YksTrackData(
      total: 903984,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1),
        YksRankPoint(450, 211),
        YksRankPoint(400, 3269),
        YksRankPoint(350, 39621),
        YksRankPoint(300, 116952),
        YksRankPoint(200, 903984),
      ],
    ),
    'SOZ': YksTrackData(
      total: 937848,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1),
        YksRankPoint(450, 119),
        YksRankPoint(400, 3088),
        YksRankPoint(350, 46571),
        YksRankPoint(300, 147193),
        YksRankPoint(200, 937848),
      ],
    ),
  },
  '2023': {
    'TYT': YksTrackData(
      total: 1795427,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 8070, estimated: true),
        YksRankPoint(400, 73371),
        YksRankPoint(300, 438380),
        YksRankPoint(200, 1795427),
      ],
    ),
    'SAY': YksTrackData(
      total: 645976,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 7470, estimated: true),
        YksRankPoint(400, 53760),
        YksRankPoint(300, 186170),
        YksRankPoint(200, 645976),
      ],
    ),
    'EA': YksTrackData(
      total: 972399,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 357, estimated: true),
        YksRankPoint(400, 5486),
        YksRankPoint(300, 156174),
        YksRankPoint(200, 972399),
      ],
    ),
    'SOZ': YksTrackData(
      total: 903190,
      totalIsLowerBound: true,
      points: [
        YksRankPoint(500, 1, estimated: true),
        YksRankPoint(450, 75, estimated: true),
        YksRankPoint(400, 1919),
        YksRankPoint(300, 119295),
        YksRankPoint(200, 903190),
      ],
    ),
  },
};

const List<String> yksYears = ['2023', '2024', '2025'];

const Map<String, String> yksTrackLabels = {
  'TYT': 'TYT',
  'SAY': 'Sayısal (SAY)',
  'EA': 'Eşit Ağırlık (EA)',
  'SOZ': 'Sözel (SÖZ)',
};

class YksRankEstimate {
  /// Tahmini Türkiye sıralaması (1 = en iyi).
  final int rank;

  /// Tahmini yüzdelik dilim (örn. 5.34 => %5,34).
  final double percentile;

  /// Puan tablonun en düşük noktasının (200) altında kaldıysa true; sıralama
  /// bu durumda "en az" değeridir.
  final bool belowTable;
  final bool totalIsLowerBound;
  final int total;
  const YksRankEstimate({
    required this.rank,
    required this.percentile,
    required this.belowTable,
    required this.totalIsLowerBound,
    required this.total,
  });
}

/// Verilen YKS puanı için seçilen yıl ve puan türünde tahmini Türkiye sıralaması.
YksRankEstimate? estimateYksRank(double score, String year, String track) {
  final data = yksRankData[year]?[track];
  if (data == null || data.points.isEmpty) return null;
  final pts = data.points;

  int rank;
  bool below = false;
  if (score >= pts.first.score) {
    rank = pts.first.cumulative;
  } else if (score < pts.last.score) {
    rank = pts.last.cumulative;
    below = true;
  } else {
    rank = pts.last.cumulative;
    for (int i = 0; i < pts.length - 1; i++) {
      final hi = pts[i];
      final lo = pts[i + 1];
      if (score <= hi.score && score >= lo.score) {
        final span = hi.score - lo.score;
        final frac = span == 0 ? 0.0 : (hi.score - score) / span;
        final lnC =
            math.log(hi.cumulative.toDouble()) +
            frac *
                (math.log(lo.cumulative.toDouble()) -
                    math.log(hi.cumulative.toDouble()));
        rank = math.exp(lnC).round();
        break;
      }
    }
  }
  if (rank < 1) rank = 1;
  final pct = (rank / data.total * 100).clamp(0.0, 100.0);
  return YksRankEstimate(
    rank: rank,
    percentile: pct,
    belowTable: below,
    totalIsLowerBound: data.totalIsLowerBound,
    total: data.total,
  );
}

/// 1234567 -> "1.234.567"
String formatYksNumber(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Sınav türü / adından puan türünü çıkarır. Belirlenemezse null (TYT dışı, tür seçilmeli).
/// Dönüş: 'TYT' | 'SAY' | 'EA' | 'SOZ' | 'AYT?' (AYT ama alan belli değil) | null (YKS değil)
String? detectYksTrack(String? examTypeName) {
  if (examTypeName == null) return null;
  final u = examTypeName
      .toUpperCase()
      .replaceAll('İ', 'I')
      .replaceAll('Ö', 'O')
      .replaceAll('Ü', 'U')
      .replaceAll('Ş', 'S')
      .replaceAll('Ç', 'C')
      .replaceAll('Ğ', 'G');
  if (u.contains('AYT')) {
    if (u.contains('SAYISAL') || RegExp(r'\bSAY\b').hasMatch(u)) return 'SAY';
    if (u.contains('ESIT') || RegExp(r'\bEA\b').hasMatch(u)) return 'EA';
    if (u.contains('SOZEL') || RegExp(r'\bSOZ\b').hasMatch(u)) return 'SOZ';
    return 'AYT?';
  }
  if (u.contains('TYT') || u.contains('YKS')) return 'TYT';
  return null;
}
