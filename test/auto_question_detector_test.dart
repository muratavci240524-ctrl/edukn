import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:edukn/screens/school/assessment/error_booklet/auto_question_detector.dart';

void main() {
  test('detects 2 columns x 3 questions', () {
    const w = 1200, h = 1600;
    final g = Uint8List(w * h)..fillRange(0, w * h, 255);
    void rect(int x0, int y0, int x1, int y1) {
      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          g[y * w + x] = 0;
        }
      }
    }

    void words(int x0, int y0, int len) {
      for (int x = x0; x < x0 + len; x += 40) {
        rect(x, y0, x + 33, y0 + 12);
      }
    }

    for (final cx in [100, 650]) {
      int y = 200;
      for (int q = 0; q < 3; q++) {
        // number blob + first line
        rect(cx, y, cx + 14, y + 12);
        words(cx + 30, y, 370);
        for (int l = 1; l < 5; l++) {
          words(cx + 30, y + l * 22, 390);
        }
        y += 5 * 22 + 40; // bigger gap between questions
      }
    }
    final boxes = AutoQuestionDetector.detect(g, w, h);
    expect(boxes.length, 6);
    expect(boxes.where((b) => b.column == 0).length, 3);
    expect(boxes.where((b) => b.column == 1).length, 3);
  });

  test('options block, header and footer are not separate questions', () {
    const w = 1200, h = 1600;
    final g = Uint8List(w * h)..fillRange(0, w * h, 255);
    void rect(int x0, int y0, int x1, int y1) {
      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          g[y * w + x] = 0;
        }
      }
    }

    void words(int x0, int y0, int len) {
      for (int x = x0; x < x0 + len; x += 40) {
        rect(x, y0, x + 33, y0 + 12);
      }
    }

    // header (wide logo-ish text) at top
    words(100, 90, 300);
    // footer
    words(100, 1560, 300);
    int y = 200;
    for (int q = 0; q < 3; q++) {
      rect(100, y, 114, y + 12); // hanging number
      for (int l = 0; l < 6; l++) {
        words(130, y + l * 22, 400);
      }
      y += 6 * 22 + 30; // gap before options
      for (int l = 0; l < 4; l++) {
        words(130, y + l * 22, 300); // options at text margin
      }
      y += 4 * 22 + 50; // gap before next question
    }
    final boxes = AutoQuestionDetector.detect(g, w, h);
    expect(boxes.length, 3);
    expect(boxes.first.left, greaterThan(116)); // hanging number at 100..114 excluded
    expect(boxes.first.top, greaterThan(150));
    expect(boxes.last.bottom, lessThan(1500));
  });

  test('detects shared passage block above linked questions', () {
    const w = 1200, h = 1600;
    final g = Uint8List(w * h)..fillRange(0, w * h, 255);
    void rect(int x0, int y0, int x1, int y1) {
      for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++) {
          g[y * w + x] = 0;
        }
      }
    }

    void words(int x0, int y0, int len) {
      for (int x = x0; x < x0 + len; x += 40) {
        rect(x, y0, x + 33, y0 + 12);
      }
    }

    // Shared passage (5 lines, no hanging question number) at y=220..330
    for (int l = 0; l < 5; l++) {
      words(130, 220 + l * 22, 420);
    }

    // Linked questions 13, 14 below the passage
    int y = 420;
    for (int q = 0; q < 2; q++) {
      rect(100, y, 114, y + 12);
      for (int l = 0; l < 5; l++) {
        words(130, y + l * 22, 400);
      }
      y += 5 * 22 + 55;
    }

    final boxes = AutoQuestionDetector.detect(g, w, h);
    expect(boxes.length, 3);
    expect(boxes.first.isPassage, isTrue);
    expect(boxes[1].isPassage, isFalse);
    expect(boxes[2].isPassage, isFalse);
  });
}
