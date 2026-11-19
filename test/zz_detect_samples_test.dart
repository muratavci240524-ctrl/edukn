import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:edukn/screens/school/assessment/error_booklet/auto_question_detector.dart';

/// Runs the detector on test/samples/sayfa_*.png and writes overlay images to
/// build/detect_out/. Not an assertion test, it is a visual tuning helper.
void main() {
  test('detect on sample pages', () {
    final dir = Directory('test/samples');
    final out = Directory('build/detect_out')..createSync(recursive: true);
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => RegExp(r'sayfa_\d+\.png$').hasMatch(f.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final expectedCounts = {
      'sayfa_1.png': 2,
      'sayfa_2.png': 2,
      'sayfa_3.png': 3,
      'sayfa_4.png': 4,
    };
    for (final f in files) {
      var im = img.decodePng(f.readAsBytesSync())!;
      im = img.copyResize(
        im,
        width: 1200,
        interpolation: img.Interpolation.cubic,
      );
      final w = im.width, h = im.height;
      final rgba = List<int>.filled(w * h * 4, 255);
      final gray = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          final i = y * w + x;
          rgba[i * 4] = p.r.toInt();
          rgba[i * 4 + 1] = p.g.toInt();
          rgba[i * 4 + 2] = p.b.toInt();
          gray[i] = (p.r * 77 + p.g * 151 + p.b * 28).toInt() >> 8;
        }
      }
      final textGray = AutoQuestionDetector.textGrayFromRgba(rgba, w * h);
      AutoQuestionDetector.debug = true;
      // ignore: avoid_print
      print(f.path);
      final boxes = AutoQuestionDetector.detect(gray, w, h, textGray: textGray);
      final name = f.path.split(RegExp(r'[\\/]')).last;
      // ignore: avoid_print
      print('$name: ${boxes.map((b) => '[${b.left.round()},${b.top.round()}..${b.right.round()},${b.bottom.round()}]').join(' ')}');
      if (expectedCounts.containsKey(name)) {
        expect(boxes.length, expectedCounts[name], reason: name);
      }
    }
  });
}
