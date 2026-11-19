import 'dart:math' as math;
import 'dart:typed_data';

/// Detected rectangle in the pixel space of the analysed image.
class DetectedBox {
  final double left, top, right, bottom;
  final int column;
  final bool isPassage;
  const DetectedBox(this.left, this.top, this.right, this.bottom, this.column,
      {this.isPassage = false});
}

class _Run {
  final int a, b; // inclusive
  _Run(this.a, this.b);
  int get len => b - a + 1;
}

class _Rect {
  int x0, y0, x1, y1; // inclusive
  _Rect(this.x0, this.y0, this.x1, this.y1);
  int get w => x1 - x0 + 1;
  int get h => y1 - y0 + 1;
}

class _MutBox {
  double left, top, right, bottom;
  bool isPassage;
  _MutBox(this.left, this.top, this.right, this.bottom,
      {this.isPassage = false});
}

/// Free, rule-based question detector for scanned exam pages.
///
/// Input is an 8-bit grayscale image (0 = black, 255 = white).
///
/// 1. Binarise (text mask: coloured decorations are ignored) and remove rules.
/// 2. Recursive XY-cut: split the page by blank horizontal bands and blank
///    vertical corridors (handles full width sections, 2 columns and mixes of
///    both on the same page; dashed column separators are ignored).
/// 3. In every resulting block, find question starts (small number blob
///    hanging at the left of the text margin) and build one box per question.
/// 4. Blocks without a number (answer options separated by a big gap) are
///    attached to the question above; headers / footers are dropped.
class AutoQuestionDetector {
  static bool debug = false;

  /// Builds the grayscale used for text detection: strongly coloured pixels
  /// (yellow bands, blue logos, pink lines) become white. Also wipes full-width
  /// coloured header/footer banners near the top and bottom of the page.
  /// [rgba] is a flat RGBA array (canvas ImageData style).
  static Uint8List textGrayFromRgba(List<int> rgba, int count,
      {int satLimit = 28}) {
    final g = Uint8List(count);
    for (int i = 0, j = 0; i < count; i++, j += 4) {
      final r = rgba[j], gg = rgba[j + 1], b = rgba[j + 2];
      final mx = math.max(r, math.max(gg, b));
      final mn = math.min(r, math.min(gg, b));
      if (mx - mn > satLimit || (b - r > 18 && b > 45)) {
        g[i] = 255;
      } else {
        g[i] = (r * 77 + gg * 151 + b * 28) >> 8;
      }
    }
    return g;
  }

  /// [gapFactor] < 1 = more questions (small gaps accepted), > 1 = fewer.
  /// [textGray]: same image with coloured pixels removed (see
  /// [textGrayFromRgba]); [gray] is the plain luminance image.
  static List<DetectedBox> detect(Uint8List gray, int w, int h,
      {double gapFactor = 1.0, Uint8List? textGray}) {
    if (w < 50 || h < 50) return [];
    final ink = _binarise(textGray ?? gray, w, h);
    _removeRules(ink, w, h);
    final full = textGray == null ? ink : _binarise(gray, w, h);
    _clearBorders(ink, w, h, gray: gray, textGray: textGray);
    if (!identical(full, ink)) {
      _clearBorders(full, w, h, gray: gray, textGray: textGray);
    }

    final leaves = <_Rect>[];
    _split(ink, w, h, _Rect(0, 0, w - 1, h - 1), leaves, gapFactor, 0);

    final boxes = <_MutBox>[];
    final orphans = <_Rect>[];
    for (final leaf in leaves) {
      final bs = _detectInBlock(ink, full, w, h, leaf, gapFactor);
      if (bs.isEmpty) {
        orphans.add(leaf);
      } else {
        boxes.addAll(bs);
      }
    }

    // Attach multi-line orphans (answer options) to the question above.
    for (final o in orphans) {
      final runs = _lineRuns(ink, w, h, o);
      if (runs.length < 2) continue; // footer / page labels
      _MutBox? best;
      double bestScore = 0;
      for (final b in boxes) {
        if (o.y0 < b.bottom - 4) continue; // must be below
        final gapV = o.y0 - b.bottom;
        if (gapV > h * 0.22) continue;
        final ov = math.min(o.x1, b.right) - math.max(o.x0, b.left);
        final frac = ov / o.w;
        if (frac < 0.6) continue;
        final score = frac * 1000 - gapV;
        if (best == null || score > bestScore) {
          best = b;
          bestScore = score;
        }
      }
      if (best != null) {
        best.bottom = math.max(best.bottom, o.y1 + 6.0);
        best.left = math.min(best.left, o.x0 - 4.0);
        best.right = math.max(best.right, o.x1 + 6.0);
      } else if (runs.length >= 3 &&
          o.y1 > h * 0.165 &&
          o.y0 < h * 0.85 &&
          o.w >= w * 0.22 &&
          o.h >= h * 0.05) {
        // Standalone shared passage ("13-15. soruları aşağıdaki metne göre...")
        // sitting above one or more questions.
        final belowIdx = boxes.indexWhere((b) =>
            b.top >= o.y1 - 12 &&
            math.min(o.x1, b.right) - math.max(o.x0, b.left) >= o.w * 0.4);
        if (belowIdx != -1) {
          final pb = _MutBox(
            math.max(0, o.x0 - 6).toDouble(),
            math.max(0, o.y0 - 6).toDouble(),
            math.min(w - 1, o.x1 + 6).toDouble(),
            math.min(h - 1, o.y1 + 6).toDouble(),
            isPassage: true,
          );
          boxes.insert(belowIdx, pb);
        }
      }
    }

    return boxes
        .map((b) => DetectedBox(
            math.max(0, b.left),
            math.max(0, b.top),
            math.min(w - 1, b.right),
            math.min(h - 1, b.bottom),
            b.left >= w * 0.45 ? 1 : 0,
            isPassage: b.isPassage))
        .toList();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // XY-cut
  static void _split(Uint8List ink, int w, int h, _Rect r, List<_Rect> out,
      double gapFactor, int depth) {
    if (r.w < 20 || r.h < 8) return;

    // horizontal projection
    final tolRow = math.max(2, (r.w * 0.004).round());
    final rows = List<int>.filled(r.h, 0);
    for (int y = r.y0; y <= r.y1; y++) {
      final o = y * w;
      int c = 0;
      for (int x = r.x0; x <= r.x1; x++) {
        c += ink[o + x];
      }
      rows[y - r.y0] = c;
    }
    final hMin = math.max(10, (h * 0.032 * gapFactor).round());
    final segs = <_Run>[];
    int s = -1, lastInk = -1;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i] > tolRow) {
        if (s == -1) {
          s = i;
        } else if (i - lastInk - 1 >= hMin) {
          segs.add(_Run(s, lastInk));
          s = i;
        }
        lastInk = i;
      }
    }
    if (s != -1) segs.add(_Run(s, lastInk));
    if (segs.isEmpty) return;
    if (segs.length > 1 && depth < 12) {
      for (final sg in segs) {
        _split(ink, w, h, _Rect(r.x0, r.y0 + sg.a, r.x1, r.y0 + sg.b), out,
            gapFactor, depth + 1);
      }
      return;
    }
    final y0 = r.y0 + segs.first.a;
    final y1 = r.y0 + segs.first.b;

    // vertical projection
    final regionH = y1 - y0 + 1;
    final cols = List<int>.filled(r.w, 0);
    for (int y = y0; y <= y1; y++) {
      final o = y * w;
      for (int x = r.x0; x <= r.x1; x++) {
        cols[x - r.x0] += ink[o + x];
      }
    }
    // erase dashed / dotted vertical separators (narrow tall peaks)
    for (int i = 5; i < cols.length - 5; i++) {
      final neigh = math.max(cols[i - 5], cols[i + 5]);
      if (cols[i] >= regionH * 0.03 && cols[i] >= 2.0 * math.max(1, neigh)) {
        for (int k = i - 2; k <= i + 2; k++) {
          if (k < 0 || k >= cols.length) continue;
          for (int y = y0; y <= y1; y++) {
            ink[y * w + r.x0 + k] = 0;
          }
          cols[k] = 0;
        }
      }
    }

    final tolCol = math.max(2, (regionH * 0.02).round());
    int fx = 0, lx = cols.length - 1;
    while (fx < lx && cols[fx] <= 0) {
      fx++;
    }
    while (lx > fx && cols[lx] <= 0) {
      lx--;
    }
    final tight = _Rect(r.x0 + fx, y0, r.x0 + lx, y1);

    final vMin = math.max(10, (w * 0.012).round());
    if (regionH >= h * 0.18 && tight.w > 60 && depth < 12) {
      int bestStart = -1, bestLen = 0, cur = -1;
      for (int x = fx + (tight.w * 0.15).round();
          x <= lx - (tight.w * 0.15).round();
          x++) {
        if (cols[x] <= tolCol) {
          cur = cur == -1 ? x : cur;
          final l = x - cur + 1;
          if (l > bestLen) {
            bestLen = l;
            bestStart = cur;
          }
        } else {
          cur = -1;
        }
      }
      // each side must hold a substantial part of the ink (otherwise we would
      // cut off a number or a decoration from its text)
      int totalInk = 0, leftInk = 0;
      for (int x = 0; x < cols.length; x++) {
        totalInk += cols[x];
        if (x < bestStart) leftInk += cols[x];
      }
      final balanced = bestLen >= vMin &&
          leftInk >= totalInk * 0.15 &&
          (totalInk - leftInk) >= totalInk * 0.15;
      if (balanced) {
        // cut 20% into the corridor: numbers hug the text on its right side
        final cutA = r.x0 + bestStart + (bestLen * 0.2).round();
        final cutB = cutA + 1;
        _split(ink, w, h, _Rect(tight.x0, y0, cutA, y1), out, gapFactor, depth + 1);
        _split(ink, w, h, _Rect(cutB, y0, tight.x1, y1), out, gapFactor, depth + 1);
        return;
      }
    }
    out.add(tight);
  }

  // ───────────────────────────────────────────────────────────────────────────
  static Uint8List _binarise(Uint8List gray, int w, int h) {
    final hist = List<int>.filled(256, 0);
    for (int i = 0; i < gray.length; i++) {
      hist[gray[i]]++;
    }
    final target = (gray.length * 0.85).round();
    int acc = 0, bg = 255;
    for (int v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= target) {
        bg = v;
        break;
      }
    }
    final thr = math.max(60, (bg * 0.70).round());
    final ink = Uint8List(w * h);
    for (int i = 0; i < ink.length; i++) {
      ink[i] = gray[i] < thr ? 1 : 0;
    }
    return ink;
  }

  /// Scans often have a dark line at the page edge, plus exam header/footer
  /// banners: ignore the outer margins and header/footer bands.
  static void _clearBorders(Uint8List m, int w, int h,
      {Uint8List? gray, Uint8List? textGray}) {
    final bx = (w * 0.025).round();
    int topY = (h * 0.085).round();
    int botY = (h * 0.945).round();
    if (gray != null && textGray != null) {
      final minCol = (w * 0.50).round();
      final maxTop = (h * 0.125).round();
      for (int y = 0; y < maxTop; y++) {
        final o = y * w;
        int col = 0;
        for (int x = 0; x < w; x++) {
          if (textGray[o + x] - gray[o + x] > 10) col++;
        }
        if (col >= minCol && y + 10 > topY) topY = y + 10;
      }
      final minBot = (h * 0.88).round();
      for (int y = h - 1; y >= minBot; y--) {
        final o = y * w;
        int col = 0;
        for (int x = 0; x < w; x++) {
          if (textGray[o + x] - gray[o + x] > 10) col++;
        }
        if (col >= minCol && y - 10 < botY) botY = y - 10;
      }
    }
    for (int y = 0; y < h; y++) {
      final o = y * w;
      if (y < topY || y >= botY) {
        m.fillRange(o, o + w, 0);
        continue;
      }
      for (int x = 0; x < bx; x++) {
        m[o + x] = 0;
      }
      for (int x = w - bx; x < w; x++) {
        m[o + x] = 0;
      }
    }
  }

  /// Erase very long straight lines (frames, underlines).
  static void _removeRules(Uint8List ink, int w, int h) {
    final minV = (h * 0.5).round();
    for (int x = 0; x < w; x++) {
      int run = 0;
      for (int y = 0; y <= h; y++) {
        final v = y < h ? ink[y * w + x] : 0;
        if (v == 1) {
          run++;
        } else {
          if (run >= minV) {
            for (int k = y - run; k < y; k++) {
              ink[k * w + x] = 0;
            }
          }
          run = 0;
        }
      }
    }
    final minH = (w * 0.30).round();
    for (int y = 0; y < h; y++) {
      int run = 0;
      final o = y * w;
      for (int x = 0; x <= w; x++) {
        final v = x < w ? ink[o + x] : 0;
        if (v == 1) {
          run++;
        } else {
          if (run >= minH) {
            for (int k = x - run; k < x; k++) {
              ink[o + k] = 0;
            }
          }
          run = 0;
        }
      }
    }
  }

  /// Text line runs (row bands containing ink) inside a block.
  static List<_Run> _lineRuns(Uint8List ink, int w, int h, _Rect r) {
    final minPx = math.max(3, (r.w * 0.006).round());
    final rowCnt = List<int>.filled(r.h, 0);
    for (int y = r.y0; y <= r.y1; y++) {
      int c = 0;
      final o = y * w;
      for (int x = r.x0; x <= r.x1; x++) {
        c += ink[o + x];
      }
      rowCnt[y - r.y0] = c;
    }
    final rawRuns = <_Run>[];
    int start = -1;
    for (int y = r.y0; y <= r.y1 + 1; y++) {
      final on = y <= r.y1 && rowCnt[y - r.y0] >= minPx;
      if (on) {
        start = start == -1 ? y : start;
      } else if (start != -1) {
        rawRuns.add(_Run(start, y - 1));
        start = -1;
      }
    }
    // Split multi-line runs where descenders barely touch ascenders
    final runs = <_Run>[];
    final valleyMax = math.max(8, (r.w * 0.02).round());
    for (final rr in rawRuns) {
      if (rr.len <= 30) {
        runs.add(rr);
        continue;
      }
      int curA = rr.a;
      int y = rr.a + 12;
      while (y <= rr.b - 10) {
        final c = rowCnt[y - r.y0];
        if (c <= valleyMax &&
            c <= rowCnt[y - 1 - r.y0] &&
            c <= rowCnt[y + 1 - r.y0] &&
            (c < rowCnt[y - 3 - r.y0] || c < rowCnt[y + 3 - r.y0])) {
          runs.add(_Run(curA, y - 1));
          while (y <= rr.b - 6 && rowCnt[y - r.y0] <= valleyMax) {
            y++;
          }
          curA = y;
          y = curA + 12;
        } else {
          y++;
        }
      }
      if (curA <= rr.b) runs.add(_Run(curA, rr.b));
    }
    final merged = <_Run>[];
    for (final r2 in runs) {
      if (merged.isNotEmpty &&
          r2.a - merged.last.b <= 2 &&
          r2.b - merged.last.a <= 24) {
        final last = merged.removeLast();
        merged.add(_Run(last.a, r2.b));
      } else {
        merged.add(r2);
      }
    }
    return merged.where((r2) => r2.len >= 4).toList();
  }

  static bool _rowHasInk(Uint8List m, int w, int y, int x0, int x1) {
    int c = 0;
    final o = y * w;
    for (int x = x0; x <= x1; x++) {
      c += m[o + x];
      if (c >= 2) return true;
    }
    return false;
  }

  /// Finds questions inside one block (usually exactly one, sometimes a
  /// stacked column with several). Returns [] if the block has no number.
  static List<_MutBox> _detectInBlock(Uint8List ink, Uint8List full, int w,
      int h, _Rect blk, double gapFactor) {
    final x0 = blk.x0, x1 = blk.x1;
    if (x1 - x0 < 30) return [];
    final runs = _lineRuns(ink, w, h, blk)
        .where((r) => r.b >= h * 0.04 && r.a <= h * 0.955)
        .toList();
    if (runs.length < 2) return [];

    final gaps = <int>[];
    for (int i = 1; i < runs.length; i++) {
      gaps.add(runs[i].a - runs[i - 1].b - 1);
    }
    final sortedGaps = [...gaps]..sort();
    final medGap = math.max(2, sortedGaps[sortedGaps.length ~/ 2]);
    final heights = runs.map((r) => r.len).toList()..sort();
    final medH = heights[heights.length ~/ 2];

    final lefts = <int>[];
    for (final r in runs) {
      lefts.add(_leftEdge(ink, w, x0, x1, r));
    }
    final sl = [...lefts]..sort();
    final textMargin = sl[sl.length ~/ 2];
    final leftMost = sl[(sl.length * 0.1).floor()];
    final bigThr = math.max(medGap * 2.0, medH * 0.9) * gapFactor;
    // The first number in a block may follow a header with a smaller gap.
    final firstThr = math.max(medGap * 1.3, medH * 0.45) * gapFactor;

    List<int> pickStarts(bool hanging) {
      final res = <int>[];
      for (int i = 0; i < runs.length; i++) {
        final gapAbove = i == 0 ? 9999 : gaps[i - 1];
        if (runs[i].b < h * 0.115) continue; // page header band
        if (i != 0 && gapAbove < (res.isEmpty ? firstThr : bigThr)) {
          continue;
        }
        final ok = hanging
            ? _looksLikeNumber(ink, w, x0, x1, runs[i], medH, textMargin, true)
            : _looksLikeNumber(ink, w, x0, x1, runs[i], medH, leftMost, false);
        if (ok) res.add(i);
      }
      return res;
    }

    var starts = pickStarts(true);
    if (starts.isEmpty) starts = pickStarts(false);
    if (starts.isEmpty) return [];

    // Answer options (A) B) C) D) ) also look like hanging numbers. A run of
    // 3+ consecutive starts whose blocks are all short is an options list:
    // drop them (they stay inside the question above).
    int blockH(int s) {
      final endIdx = (s + 1 < starts.length ? starts[s + 1] : runs.length) - 1;
      return runs[endIdx].b - runs[starts[s]].a + 1;
    }

    final keep = List<bool>.filled(starts.length, true);
    int i0 = 0;
    while (i0 < starts.length) {
      if (blockH(i0) < medH * 3.5) {
        int j = i0;
        while (j < starts.length && blockH(j) < medH * 3.5) {
          j++;
        }
        if (j - i0 >= 3) {
          for (int k = i0; k < j; k++) {
            keep[k] = false;
          }
        }
        i0 = j;
      } else {
        i0++;
      }
    }
    starts = [
      for (int k = 0; k < starts.length; k++)
        if (keep[k]) starts[k]
    ];
    if (starts.isEmpty) return [];

    // tiny blocks are merged into the previous question
    bool changed = true;
    while (changed && starts.length > 1) {
      changed = false;
      for (int s = 0; s < starts.length - 1; s++) {
        final endIdx = starts[s + 1] - 1;
        final height = runs[endIdx].b - runs[starts[s]].a + 1;
        if (height < medH * 3.5) {
          starts.removeAt(s + 1);
          changed = true;
          break;
        }
      }
    }

    // a trailing start with only one line is a footer / page number
    if (starts.length > 1 && runs.length - starts.last <= 1) {
      starts.removeLast();
    }

    final boxes = <_MutBox>[];
    // If there is a multi-line shared passage above the first question in this
    // block (and it is not the 2-line page-top DİKKAT instruction box), emit it
    // as a passage box.
    if (starts.first >= 3 &&
        runs[starts.first - 1].b > h * 0.165 &&
        runs[starts.first - 1].b - runs.first.a >= medH * 2.8) {
      final pTop = runs.first.a;
      final pBot = runs[starts.first - 1].b;
      int px0 = x1, px1 = x0;
      for (int y = pTop; y <= pBot; y++) {
        final o = y * w;
        for (int x = x0; x <= x1; x++) {
          if (full[o + x] == 1) {
            if (x < px0) px0 = x;
            if (x > px1) px1 = x;
          }
        }
      }
      if (px1 > px0) {
        boxes.add(_MutBox(
          math.max(0, px0 - 6).toDouble(),
          math.max(0, pTop - 6).toDouble(),
          math.min(w - 1, px1 + 6).toDouble(),
          math.min(h - 1, pBot + 6).toDouble(),
          isPassage: true,
        ));
      }
    }
    for (int s = 0; s < starts.length; s++) {
      final first = runs[starts[s]];
      var lastIdx = (s + 1 < starts.length ? starts[s + 1] : runs.length) - 1;
      if (s + 1 == starts.length) {
        final cut = math.max(medGap * 3.5, medH * 2.2) * gapFactor;
        for (int k = starts[s] + 1; k <= lastIdx; k++) {
          if (runs[k].a - runs[k - 1].b - 1 >= cut && runs.length - k <= 3) {
            lastIdx = k - 1;
            break;
          }
        }
      }
      final last = runs[lastIdx];

      // vertical extent: text runs, extended through the full mask so that
      // pictures / coloured diagrams are kept
      int top = first.a, bottom = last.b;
      final topLimit = math.max(first.a - 8, starts[s] > 0 ? runs[starts[s] - 1].b + 1 : blk.y0);
      int gapRows = 0;
      for (int y = top - 1; y >= topLimit && gapRows < 4; y--) {
        if (_rowHasInk(full, w, y, x0, x1)) {
          top = y;
          gapRows = 0;
        } else {
          gapRows++;
        }
      }
      final bottomLimit =
          lastIdx + 1 < runs.length ? runs[lastIdx + 1].a - 1 : blk.y1;
      gapRows = 0;
      for (int y = bottom + 1; y <= bottomLimit && gapRows < 4; y++) {
        if (_rowHasInk(full, w, y, x0, x1)) {
          bottom = y;
          gapRows = 0;
        } else {
          gapRows++;
        }
      }

      // Exclude the hanging question number (e.g. "1.", "2.") on the left so
      // the cropped question can be reused with a new number.
      final numEnd = _hangingNumberEnd(ink, w, x0, x1, first, medH, textMargin);
      final minX = numEnd != null ? math.min(x1, numEnd + 3) : x0;

      // horizontal extent: text first, then grow through dense picture
      // columns that touch it (decorations further away are ignored)
      int bx0 = x1, bx1 = minX;
      final colFull = List<int>.filled(x1 - x0 + 1, 0);
      for (int y = top; y <= bottom; y++) {
        final o = y * w;
        for (int x = minX; x <= x1; x++) {
          if (ink[o + x] == 1) {
            if (x < bx0) bx0 = x;
            if (x > bx1) bx1 = x;
          }
          if (full[o + x] == 1) colFull[x - x0]++;
        }
      }
      if (bx1 > bx0) {
        final dense = math.max(3, ((bottom - top) * 0.12).round());
        int gapC = 0;
        for (int x = bx1 + 1; x <= x1 && gapC < 12; x++) {
          if (colFull[x - x0] >= dense) {
            bx1 = x;
            gapC = 0;
          } else {
            gapC++;
          }
        }
        gapC = 0;
        for (int x = bx0 - 1; x >= minX && gapC < 12; x--) {
          if (colFull[x - x0] >= dense) {
            bx0 = x;
            gapC = 0;
          } else {
            gapC++;
          }
        }
      }
      if (bx1 <= bx0) continue;
      const pad = 6;
      final leftEdge = numEnd != null
          ? math.max(numEnd + 3, bx0 - 4).toDouble()
          : math.max(0, bx0 - pad).toDouble();
      boxes.add(_MutBox(
        leftEdge,
        math.max(0, top - pad).toDouble(),
        math.min(w - 1, bx1 + pad).toDouble(),
        math.min(h - 1, bottom + pad).toDouble(),
      ));
    }
    return boxes;
  }

  static int _leftEdge(Uint8List ink, int w, int x0, int x1, _Run r) {
    for (int x = x0; x <= x1; x++) {
      int c = 0;
      for (int y = r.a; y <= r.b; y++) {
        c += ink[y * w + x];
      }
      if (c >= 1) return x;
    }
    return x0;
  }

  /// Small blob (the question number, e.g. "12." ) at the left of the line.
  static bool _looksLikeNumber(Uint8List ink, int w, int x0, int x1, _Run r,
      int medH, int margin, bool hanging) {
    final limit = math.min(x1, margin + math.max(60, medH * 7));
    final offset = x0;
    final proj = <int>[];
    for (int x = offset; x <= limit; x++) {
      int c = 0;
      for (int y = r.a; y <= r.b; y++) {
        c += ink[y * w + x];
      }
      proj.add(c);
    }
    final gapMax = math.max(4, (medH * 0.6).round());
    final clusters = <_Run>[];
    int cs = -1, lastInk = -1;
    for (int i = 0; i < proj.length; i++) {
      if (proj[i] > 0) {
        if (cs == -1) {
          cs = i;
        } else if (i - lastInk > gapMax) {
          clusters.add(_Run(cs, lastInk));
          cs = i;
        }
        lastInk = i;
      }
    }
    if (cs != -1) clusters.add(_Run(cs, lastInk));
    if (clusters.isEmpty) return false;

    // skip tiny specks (dotted separator residue, noise) before the number
    final minW = math.max(3, medH * 0.3);
    final valid = clusters.where((c) => c.len >= minW).toList();
    if (valid.isEmpty) return false;
    final c0 = valid.first;
    final absStart = offset + c0.a;
    final absEnd = offset + c0.b;
    if (c0.len < math.max(3, medH * 0.3) || c0.len > medH * 2.2) return false;

    if (hanging) {
      final hang = math.max(5, (medH * 0.5).round());
      if (absStart > margin - hang) return false;
      if (absEnd > margin + medH * 0.5) return false;
      // the text of the question must start at the text margin right after
      // the number (a header or a decoration has nothing there)
      final later = valid.skip(1).toList();
      if (later.isNotEmpty) {
        final ns = offset + later.first.a;
        final atMargin = ns >= margin - 8 && ns <= margin + medH * 1.2;
        final closeToNumber = ns - absEnd >= medH * 0.4 && ns - absEnd <= medH * 1.6;
        if (!atMargin && !closeToNumber) return false;
      }
    } else {
      if (absStart - margin > math.max(30, medH * 3.0)) return false;
    }
    return true;
  }

  /// Returns the right X coordinate of the hanging question number blob on [r],
  /// or null if no hanging number blob is found.
  static int? _hangingNumberEnd(
      Uint8List ink, int w, int x0, int x1, _Run r, int medH, int margin) {
    final limit = math.min(x1, margin + math.max(60, medH * 7));
    final proj = <int>[];
    for (int x = x0; x <= limit; x++) {
      int c = 0;
      for (int y = r.a; y <= r.b; y++) {
        c += ink[y * w + x];
      }
      proj.add(c);
    }
    final gapMax = math.max(4, (medH * 0.6).round());
    final clusters = <_Run>[];
    int cs = -1, lastInk = -1;
    for (int i = 0; i < proj.length; i++) {
      if (proj[i] > 0) {
        if (cs == -1) {
          cs = i;
        } else if (i - lastInk > gapMax) {
          clusters.add(_Run(cs, lastInk));
          cs = i;
        }
        lastInk = i;
      }
    }
    if (cs != -1) clusters.add(_Run(cs, lastInk));
    final minW = math.max(3, medH * 0.3);
    final valid = clusters.where((c) => c.len >= minW).toList();
    if (valid.isEmpty) return null;
    final c0 = valid.first;
    final absStart = x0 + c0.a;
    final absEnd = x0 + c0.b;
    final hang = math.max(5, (medH * 0.5).round());
    if (absStart <= margin - hang && absEnd <= margin + medH * 0.5) {
      return absEnd;
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  /// Shrinks a rough user selection to the ink it actually contains, so the
  /// white margins on every side are removed. Coordinates are in the pixel
  /// space of [gray]. Returns null if the region holds (almost) no ink.
  static DetectedBox? tighten(Uint8List gray, int w, int h, double l, double t,
      double r, double b, {int pad = 3}) {
    final ink = _binarise(gray, w, h);
    _clearBorders(ink, w, h);
    final x0 = l.floor().clamp(0, w - 1);
    final x1 = r.ceil().clamp(0, w - 1);
    final y0 = t.floor().clamp(0, h - 1);
    final y1 = b.ceil().clamp(0, h - 1);
    if (x1 - x0 < 4 || y1 - y0 < 4) return null;
    final cols = List<int>.filled(x1 - x0 + 1, 0);
    final rows = List<int>.filled(y1 - y0 + 1, 0);
    for (int y = y0; y <= y1; y++) {
      final o = y * w;
      for (int x = x0; x <= x1; x++) {
        if (ink[o + x] == 1) {
          cols[x - x0]++;
          rows[y - y0]++;
        }
      }
    }
    // Erase narrow vertical dashed/solid column separator lines if the rough
    // selection crossed a column divider near its left or right edge.
    final regionH = y1 - y0 + 1;
    for (int i = 3; i < cols.length - 3; i++) {
      final neigh = math.max(cols[i - 3], cols[i + 3]);
      if (cols[i] >= regionH * 0.04 && cols[i] >= 2.2 * math.max(1, neigh)) {
        for (int k = i - 2; k <= i + 2; k++) {
          if (k < 0 || k >= cols.length) continue;
          for (int y = y0; y <= y1; y++) {
            if (ink[y * w + x0 + k] == 1) {
              ink[y * w + x0 + k] = 0;
              rows[y - y0]--;
            }
          }
          cols[k] = 0;
        }
      }
    }

    int fx = -1, lx = -1, fy = -1, ly = -1;
    for (int i = 0; i < cols.length; i++) {
      if (cols[i] >= 2) {
        if (fx == -1) fx = i;
        lx = i;
      }
    }
    for (int i = 0; i < rows.length; i++) {
      if (rows[i] >= 2) {
        if (fy == -1) fy = i;
        ly = i;
      }
    }
    if (fx == -1 || fy == -1 || lx - fx < 4 || ly - fy < 4) return null;

    // If the selection includes a hanging question number (e.g. "1.", "10.") at
    // the top-left, the lines below the first line (y > y0 + fy + 32) all start
    // at `bodyLeft` while the hanging number sits in [fx .. bodyLeft - 1] only
    // in the top ~32px.
    if (ly - fy > 45 && lx - fx > 60) {
      int bodyLeft = -1;
      final maxSearch = math.min(lx - 30, fx + 52);
      for (int cx = fx; cx <= maxSearch; cx++) {
        int lowerInk = 0;
        for (int y = y0 + fy + 32; y <= y0 + ly; y++) {
          lowerInk += ink[y * w + x0 + cx];
        }
        if (lowerInk >= 2) {
          bodyLeft = cx;
          break;
        }
      }
      if (bodyLeft != -1 && bodyLeft - fx >= 6 && bodyLeft - fx <= 48) {
        // Verify there is a vertical gap in the top 32px just before bodyLeft
        bool hasGapBeforeBody = false;
        for (int gx = math.max(fx + 2, bodyLeft - 12); gx < bodyLeft; gx++) {
          int topInk = 0;
          for (int y = y0 + fy; y < math.min(y0 + ly, y0 + fy + 32); y++) {
            topInk += ink[y * w + x0 + gx];
          }
          if (topInk == 0) {
            hasGapBeforeBody = true;
            break;
          }
        }
        if (hasGapBeforeBody) {
          fx = bodyLeft;
        }
      }
    }
    return DetectedBox(
      math.max(0, x0 + fx - pad).toDouble(),
      math.max(0, y0 + fy - pad).toDouble(),
      math.min(w - 1, x0 + lx + pad).toDouble(),
      math.min(h - 1, y0 + ly + pad).toDouble(),
      0,
    );
  }

  /// When a shared passage ("Ortak Metin") is pinned, the original exam often
  /// has a single-line instruction at the very top such as:
  /// "4, 5 ve 6. soruları aşağıdaki metne göre cevaplayınız."
  /// Since question numbers change in the student's Error Booklet and a new
  /// dynamic header is generated above the passage, this helper trims off a
  /// standalone 1-line instruction at the top of the passage if present.
  static DetectedBox? stripLeadingInstructionLine(Uint8List gray, int w, int h,
      double l, double t, double r, double b,
      {int pad = 3}) {
    final base = tighten(gray, w, h, l, t, r, b, pad: pad);
    if (base == null) return null;
    final ink = _binarise(gray, w, h);
    final x0 = base.left.floor().clamp(0, w - 1);
    final x1 = base.right.ceil().clamp(0, w - 1);
    final y0 = base.top.floor().clamp(0, h - 1);
    final y1 = base.bottom.ceil().clamp(0, h - 1);
    if (y1 - y0 < 55 || x1 - x0 < 80) return base;

    final rows = List<int>.filled(y1 - y0 + 1, 0);
    for (int y = y0; y <= y1; y++) {
      final o = y * w;
      for (int x = x0; x <= x1; x++) {
        rows[y - y0] += ink[o + x];
      }
    }
    final runs = <_Run>[];
    int rs = -1, lastY = -1;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i] >= 2) {
        if (rs == -1) {
          rs = i;
        } else if (i - lastY > 2) {
          runs.add(_Run(rs, lastY));
          rs = i;
        }
        lastY = i;
      }
    }
    if (rs != -1) runs.add(_Run(rs, lastY));
    if (runs.length < 2) return base;

    final first = runs.first;
    final second = runs[1];
    final gapAfterFirst = second.a - first.b - 1;
    final remainingH = (y1 - y0) - second.a;

    // A standalone 1-line instruction ("4, 5 ve 6. soruları aşağıdaki metne göre...")
    // is 7..24px tall, followed by a vertical gap >= 5px, starts near the left edge
    // of the passage (not a centered title), and spans >= 38% of the box width.
    if (first.len >= 7 &&
        first.len <= 24 &&
        gapAfterFirst >= 5 &&
        remainingH >= 35) {
      int lx = x1, rx = x0;
      for (int y = y0 + first.a; y <= y0 + first.b; y++) {
        final o = y * w;
        for (int x = x0; x <= x1; x++) {
          if (ink[o + x] == 1) {
            if (x < lx) lx = x;
            if (x > rx) rx = x;
          }
        }
      }
      final lineW = rx - lx + 1;
      if (lx - x0 <= 45 && lineW >= (x1 - x0) * 0.38) {
        final newTop = math.max(0, y0 + second.a - pad).toDouble();
        return DetectedBox(base.left, newTop, base.right, base.bottom, 0);
      }
    }
    return base;
  }
}
