import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

// ---------------------------------------------------------------------------
// Harita / Sosyal bilgiler şekilleri. Tüm haritalar elle girilmiş (boylam,
// enlem) çokgenlerinden çizilir; yalnızca Canvas kullanılır.
// ---------------------------------------------------------------------------

typedef _Pr = Offset Function(double lon, double lat);

/// Türkiye izdüşümü: eşit dikdörtgen, boylam ölçeği cos(39°)≈0.78 ile düzeltilmiş.
/// Çerçeve: 24.8°D–45.8°D, 34.3°K–43.2°K → 320 × 174 birim.
Offset _tr(double lon, double lat) =>
    Offset((lon - 24.8) * 15.238, (43.2 - lat) * 19.55);

_Pr _mk(double lon0, double lat1, double sx, double sy) =>
    (double lon, double lat) => Offset((lon - lon0) * sx, (lat1 - lat) * sy);

_Pr _ws(double s) =>
    (double lon, double lat) => Offset((lon + 180) * s, (90 - lat) * s);

List<Offset> _pts(List<double> f, _Pr pr) => [
  for (int i = 0; i + 1 < f.length; i += 2) pr(f[i], f[i + 1]),
];
Path _pp(List<double> f, _Pr pr) => WbArtPen.poly(_pts(f, pr));
Path _pl(List<double> f, _Pr pr) => WbArtPen.poly(_pts(f, pr), close: false);

class _Land {
  const _Land(this.p, this.c);
  final List<double> p;
  final Color c;
}

class _Pt {
  const _Pt(this.n, this.lon, this.lat, [this.a = 'left']);
  final String n;
  final double lon;
  final double lat;
  final String a;
}

class _Reg {
  const _Reg(this.name, this.color, this.poly, this.lon, this.lat);
  final String name;
  final Color color;
  final List<double> poly;
  final double lon;
  final double lat;
}

// ------------------------- TÜRKİYE KIYI ÇİZGİLERİ ---------------------------

/// Trakya (Boğaz'ın batısı, Gelibolu yarımadası dahil).
const List<double> _thrF = [
  26.35, 41.72, 26.6, 41.82, 26.95, 41.98, 27.4, 42.05, 27.9, 42.0, //
  28.0, 41.98, 28.0, 41.9, 28.1, 41.6, 28.35, 41.45, 28.65, 41.35,
  28.9, 41.3, 29.04, 41.24, 29.0, 41.12, 28.96, 41.03, 28.9, 40.98,
  28.7, 40.97, 28.5, 41.0, 28.25, 41.07, 27.95, 40.97, 27.5, 40.97,
  27.35, 40.85, 27.25, 40.72, 27.1, 40.6, 26.9, 40.46, 26.67, 40.4,
  26.5, 40.3, 26.35, 40.18, 26.18, 40.05, 26.22, 40.28, 26.4, 40.46,
  26.65, 40.52, 26.75, 40.58, 26.45, 40.7, 26.2, 40.72, 26.08, 40.73,
  26.05, 40.85, 26.15, 41.1, 26.3, 41.4, 26.36, 41.6,
];

/// Anadolu (Boğaz'ın doğusu).
const List<double> _anaF = [
  29.12, 41.22, 29.45, 41.15, 29.6, 41.18, 30.0, 41.15, 30.25, 41.2, //
  30.75, 41.1, 31.15, 41.1, 31.4, 41.28, 31.8, 41.45, 32.1, 41.65,
  32.4, 41.75, 32.95, 41.9, 33.33, 42.02, 33.76, 41.98, 34.3, 41.9,
  34.8, 41.95, 35.0, 42.1, 35.15, 42.03, 35.4, 41.8, 35.7, 41.65,
  35.95, 41.72, 36.1, 41.6, 36.3, 41.3, 36.7, 41.3, 37.0, 41.27,
  37.9, 41.0, 38.4, 40.93, 39.0, 41.0, 39.7, 41.0, 40.5, 41.02,
  41.0, 41.25, 41.4, 41.42, 41.55, 41.52, 41.8, 41.55, 42.45, 41.48,
  42.85, 41.2, 43.2, 41.1, 43.5, 40.7, 43.7, 40.4, 43.7, 40.1,
  44.05, 40.02, 44.45, 39.75, 44.78, 39.65, 44.6, 39.4, 44.15, 39.0,
  44.4, 38.35, 44.35, 37.95, 44.7, 37.5, 44.8, 37.15, 44.2, 37.3,
  43.6, 37.2, 43.0, 37.35, 42.2, 37.33, 41.5, 37.08, 41.0, 37.1,
  40.2, 36.95, 39.5, 36.72, 38.8, 36.7, 38.2, 36.9, 37.5, 36.65,
  37.0, 36.65, 36.7, 36.3, 36.55, 36.1, 36.4, 36.0, 36.2, 35.85,
  35.95, 35.95, 35.92, 36.2, 35.88, 36.4, 36.0, 36.55, 36.15, 36.6,
  36.2, 36.85, 35.95, 36.85, 35.78, 36.77, 35.55, 36.7, 35.35, 36.55,
  34.9, 36.65, 34.65, 36.8, 34.15, 36.45, 33.9, 36.35, 33.3, 36.15,
  32.8, 36.05, 32.3, 36.25, 32.0, 36.5, 31.4, 36.75, 30.7, 36.85,
  30.55, 36.6, 30.15, 36.3, 29.6, 36.2, 29.4, 36.25, 29.1, 36.6,
  28.8, 36.7, 28.25, 36.85, 27.7, 36.65, 27.4, 36.7, 27.65, 36.9,
  27.4, 37.03, 27.6, 37.25, 27.25, 37.4, 27.25, 37.85, 26.9, 38.2,
  26.3, 38.3, 26.4, 38.65, 26.75, 38.65, 26.88, 39.07, 26.7, 39.3,
  26.9, 39.5, 26.7, 39.57, 26.4, 39.45, 26.05, 39.48, 26.15, 39.75,
  26.2, 39.95, 26.4, 40.15, 26.68, 40.35, 27.0, 40.4, 27.3, 40.4,
  27.6, 40.37, 27.75, 40.5, 27.92, 40.48, 27.97, 40.35, 28.3, 40.35,
  28.65, 40.4, 28.9, 40.38, 29.15, 40.43, 29.3, 40.65, 29.5, 40.7,
  29.95, 40.76, 29.6, 40.78, 29.4, 40.77, 29.3, 40.82, 29.2, 40.88,
  29.02, 40.98, 29.05, 41.03, 29.09, 41.1,
];

/// Kıbrıs adası.
const List<double> _cyF = [
  32.93, 35.4, 33.32, 35.34, 33.7, 35.35, 34.1, 35.5, 34.58, 35.68, //
  34.3, 35.45, 34.05, 35.2, 34.08, 34.97, 33.65, 34.93, 33.03, 34.66,
  32.9, 34.6, 32.42, 34.77, 32.27, 35.1, 32.6, 35.18, 32.85, 35.17,
];

// --------------------------- DÜNYA KARALARI ---------------------------------

const List<double> _naF = [
  -168, 66, -162, 70, -156, 71.3, -141, 69.6, -128, 70, -115, 68.5, //
  -108, 68, -96, 68.5, -90, 68.5, -86, 66.5, -82, 63.5, -93, 61,
  -94, 58.8, -90, 57, -85, 55.5, -82, 53, -79, 51.5, -78.8, 54.5,
  -77.3, 58, -78.5, 62.3, -74, 62.3, -70, 61, -65, 60.3, -62, 57.5,
  -57, 53.5, -56, 51.5, -60, 50.2, -66, 50, -70, 47.5, -65, 48.5,
  -64, 46.5, -61, 45.7, -66, 44.2, -70, 43.7, -70.5, 41.8, -74, 40.5,
  -76, 37, -75.5, 35.2, -78, 33.8, -81, 31.5, -80, 27, -80.3, 25.2,
  -82, 26.5, -83, 29.2, -85, 29.7, -89, 30.2, -90, 29, -94, 29.5,
  -97.3, 27.5, -97.8, 22.5, -97.2, 20, -95, 18.5, -91, 18.8, -90.5, 21,
  -87, 21.5, -87.5, 18, -88.2, 16, -84, 15.8, -83.3, 12, -83.7, 10.8,
  -81.5, 9, -79.5, 9.5, -77.4, 8.6, -78.2, 7.5, -80, 7.3, -81.8, 8.2,
  -85.7, 10, -87.5, 13, -91.5, 14, -94.5, 16.2, -97, 15.9, -101, 17.3,
  -105.5, 20.5, -105.5, 23, -109.3, 25.8, -112.5, 29.3, -114.8, 31.7,
  -114.2, 30, -112.8, 27.5, -111.2, 25, -109.5, 23, -110.3, 23.7,
  -112, 24.8, -114.4, 27.7, -115.7, 30, -117.1, 32.5, -118.5, 34,
  -120.6, 34.6, -122.4, 37.5, -124.2, 40.3, -124, 46, -124.7, 48.4,
  -123, 49, -127, 50.8, -130, 54.5, -133, 57, -136, 58.5, -140, 59.7,
  -146, 60.5, -150, 59.3, -152, 58.3, -154, 57.5, -158, 56.2, -163, 54.7,
  -160, 58.5, -157, 58.7, -162, 58.7, -165, 61, -166, 64, -162, 64.5,
  -168, 65.6,
];

const List<double> _glF = [
  -73, 78, -67, 80, -60, 82, -40, 83.5, -25, 83, -18, 80, -20, 75, //
  -22, 70.5, -32, 68, -40, 65, -43, 60, -48, 61, -52, 64.5, -54, 68,
  -56, 72, -60, 76, -68, 76.5,
];

const List<double> _baffinF = [
  -80, 73.5, -70, 72, -65, 67, -62, 66.5, -66, 62.5, -72, 63.2, -78, 65, //
  -74, 68.4, -85, 70,
];
const List<double> _victoriaF = [
  -118,
  72,
  -105,
  73,
  -101,
  69,
  -110,
  68.5,
  -118,
  70,
];
const List<double> _ellesF = [
  -90,
  77,
  -78,
  76,
  -62,
  82.5,
  -72,
  83.1,
  -90,
  81.5,
];
const List<double> _cubaF = [
  -85,
  22,
  -82,
  23.1,
  -77,
  21.5,
  -74.2,
  20.2,
  -78,
  20.7,
  -82,
  22.4,
];
const List<double> _hispF = [-74.4, 18.3, -72, 19.9, -68.4, 18.6, -71, 17.8];

const List<double> _saF = [
  -77.4, 8.6, -75.5, 10.8, -72, 12, -71.5, 10.5, -68, 10.6, -64, 10.6, //
  -61, 10.5, -60, 8.5, -57, 6, -52, 5, -50, 1.5, -50, 0, -48, -1,
  -44.5, -2.5, -40, -3, -35, -5.2, -34.9, -8, -37, -11.5, -39, -14,
  -39, -18, -41, -22, -44, -23.2, -48, -26, -48.5, -28, -52, -32,
  -54, -34.5, -57, -35, -57, -37.5, -62, -39, -65, -41, -63.5, -42.5,
  -67, -46, -66, -48, -69, -51, -68.5, -52.5, -65, -55, -68, -55.5,
  -72, -54, -75, -50, -74, -46, -73.5, -40, -73.5, -37, -71.5, -32,
  -71.5, -28, -70.3, -18, -76, -14, -79, -8, -81.2, -5.5, -80, -2.5,
  -80.5, 0, -79, 2, -77.3, 4, -77.9, 7.2,
];

const List<double> _euF = [
  -5.6, 36, -6.3, 36.8, -8.9, 37, -8.8, 38.5, -9.5, 38.7, -8.8, 41, //
  -8.9, 42.5, -9.3, 43, -7.7, 43.7, -4, 43.5, -1.8, 43.4, -1.3, 44.6,
  -1.2, 46.2, -2.2, 47.2, -4.7, 48, -3, 48.8, -1.6, 48.7, -1.3, 49.7,
  0.2, 49.5, 1.5, 50.2, 2.5, 51.1, 4, 51.6, 4.8, 52.9, 6.5, 53.5,
  8.5, 53.7, 8.9, 54.9, 8.1, 55.9, 8.2, 57.1, 10.5, 57.7, 10.3, 56.5,
  9.9, 55.2, 10, 54.5, 11.5, 54.1, 13.5, 54.2, 14.5, 53.9, 16.5, 54.5,
  18.7, 54.6, 19.5, 54.4, 21, 55.2, 21, 56.5, 21.5, 57.5, 23, 57,
  24, 57, 24.3, 58.4, 23.5, 59.2, 25.5, 59.6, 28, 59.5, 30, 59.9,
  29, 60.6, 27.5, 60.5, 25, 60.2, 22.9, 59.9, 21.3, 60.6, 21.5, 62,
  21.2, 63, 22.7, 64.3, 24.8, 65.2, 24, 65.8, 22, 65.7, 21.2, 64.5,
  19, 63, 17.4, 62.4, 17.2, 61, 17.5, 60.5, 18.8, 60, 18.5, 59.5,
  17, 58.7, 16.6, 57.5, 16.1, 56.2, 14.4, 55.5, 13, 55.4, 12.8, 56.4,
  12, 57.5, 11.2, 58.5, 10.7, 59.6, 9.5, 59, 8, 58.1, 6.5, 58.1,
  5.5, 59, 5, 60.8, 5.2, 62, 7, 62.9, 9, 63.7, 11, 64.8, 13, 66,
  14.5, 67.5, 16, 68.5, 18, 69.6, 20.5, 70, 23, 70.7, 26, 71, 29, 70.9,
  31, 70.2, 33, 69.4, 36, 69.2, 41, 67.5, 43, 67, 44.5, 68.5, 47, 68.3,
  53, 68.7, 58, 68.9, 60, 69, 60, 62, 59.5, 55, 61, 51, 55, 50.5,
  51.5, 49.5, 50.5, 48, 51, 47, 49, 46.5, 47.5, 45.5, 47.5, 43,
  45, 42.3, 42, 43.2, 40, 43.6, 38, 44.6, 37.4, 45.3, 36.6, 45.4,
  35, 45, 33.6, 44.4, 32.5, 45.4, 31, 46.6, 30.7, 46.5, 30.2, 45.8,
  29.7, 45.2, 28.8, 44.5, 28.6, 43.7, 27.9, 42.7, 28.0, 42.0, 29.0, 41.2,
  28.95, 41.0, 27.5, 40.95, 26.8, 40.5, 26.2, 40.1, 26.1, 40.7, 25.5, 40.85,
  24.4, 40.9, 23.7, 40.3, 23, 40.5, 22.6, 40, 22.9, 39.3, 23.5, 38.5,
  24, 37.65, 23.2, 37.9, 23.2, 36.45, 22.5, 36.4, 21.7, 36.9, 21.7, 38.2,
  21.2, 38.7, 20.8, 39.3, 20.2, 39.7, 19.5, 40.3, 19.4, 41.3, 19.1, 42,
  18.5, 42.45, 17.2, 43.1, 16.4, 43.5, 15.2, 44.1, 14.5, 45.2, 13.6, 45.7,
  12.3, 45.4, 12.3, 44.4, 13.5, 43.6, 14.5, 42.3, 16, 41.9, 16.9, 41.1,
  18.5, 40.1, 17.2, 40.4, 16.6, 39.7, 17.1, 38.9, 16.5, 38.4, 15.8, 37.95,
  16, 39, 15.6, 40.1, 14.2, 40.8, 13, 41.2, 12.3, 41.6, 11.2, 42.4,
  10.5, 42.9, 10.2, 43.9, 8.8, 44.4, 7.5, 43.8, 6.1, 43.1, 4.8, 43.4,
  3.2, 43.1, 3.1, 42.2, 0.9, 41, 0, 39.7, -0.1, 38.7, -0.7, 37.6,
  -2.2, 36.8, -4.4, 36.7,
];

const List<double> _afF = [
  -5.6, 35.9, -2, 35.1, 3, 36.8, 10, 37.2, 11, 35, 10.2, 33.5, 15, 32.3, //
  20, 32, 20, 30.5, 24, 32, 29, 30.9, 32.3, 31.2, 32.6, 29.9,
  33.5, 27.5, 35.5, 24, 37.2, 21, 37.4, 18.5, 39.5, 15.5, 41.5, 13.5,
  43.2, 12.5, 44.5, 10.5, 51, 11.8, 51.2, 10.4, 48, 5, 43, 0,
  41, -2, 39.2, -5, 39.5, -8, 40.5, -11, 40.6, -15, 36, -19,
  35, -22, 33, -26, 32.5, -28.5, 30, -31.5, 27, -33.5, 25, -34,
  22, -34.2, 20, -34.8, 18.4, -34, 17.8, -30, 16.5, -28.5, 14.5, -23,
  12, -18, 13.7, -11.5, 13.2, -8, 12, -5.5, 9.5, -1, 9.5, 3.8,
  8.5, 4.5, 6.5, 4.3, 4.5, 6.2, 1.5, 6, -2, 4.8, -4, 5.2, -7.5, 4.4,
  -11, 6.8, -13.2, 9, -14.5, 10.8, -16.7, 12.5, -17.5, 14.7, -16.5, 16.5,
  -16.3, 19.5, -17, 21, -15, 24.5, -13, 27.5, -10, 29.5, -9.8, 31.2,
  -8.5, 33.2, -6.8, 34,
];

const List<double> _asF = [
  60, 69, 66, 69.5, 67, 71, 70, 73, 75, 72.5, 80, 73.5, 87, 75.2, //
  95, 76, 100, 77.5, 105, 77.5, 113, 73.8, 120, 73, 127, 73.5, 140, 72.5,
  150, 71.5, 160, 70, 170, 70, 180, 69, 180, 65, 178, 64.5, 174, 64,
  170, 60, 164, 59.8, 163, 57.5, 162, 56, 160, 53, 156.5, 51, 155.8, 54,
  156, 57.5, 160, 61.5, 155, 59.4, 150, 59.3, 143, 59.3, 138, 55,
  137, 54, 140, 53.3, 141, 52, 140.5, 50, 140.3, 48, 138, 46,
  135.5, 43.5, 133, 42.8, 131.5, 42.5, 130.2, 42.2, 129.7, 41, 128.5, 39.5,
  127.5, 39.7, 128.4, 38.5, 129.4, 36.5, 129.3, 35.3, 127.5, 34.6,
  126.3, 34.6, 126.5, 36, 126.6, 37.5, 125.2, 37.7, 125.1, 38.7, 125, 39.6,
  124.4, 39.9, 122.5, 39.5, 121.5, 38.9, 121.2, 40.2, 122, 40.5,
  120.5, 40, 119, 39.2, 117.8, 38.8, 118.9, 37.9, 120.7, 37.8,
  122.6, 37.3, 121.5, 36.5, 120.2, 35.9, 119.2, 34.8, 120.5, 33,
  121.9, 31.8, 121.9, 30.9, 121.8, 29.5, 121.5, 28.2, 120.5, 26.8,
  119.6, 25.3, 117.5, 23.7, 116, 22.8, 114.2, 22.3, 113.5, 22.2,
  111.5, 21.5, 110.4, 21, 110.5, 20.3, 109.7, 20.3, 109.8, 21.5, 108.2, 21.5,
  106.8, 20.7, 105.8, 19, 106.5, 17.5, 107.5, 16.2, 108.7, 15, 109.3, 13,
  109.2, 11.5, 107.8, 10.5, 106.8, 10.4, 105.5, 8.7, 104.8, 10.2, 103.5, 10.6,
  102.7, 12.2, 101.4, 12.7, 100.9, 13.5, 100.1, 13.4, 99.9, 11, 99.2, 10.2,
  99.9, 8.5, 100.3, 7, 101.3, 6.3, 102.3, 6, 103.4, 4.8, 103.4, 3.5,
  104.2, 1.4, 103.4, 1.4, 101.4, 2.7, 100.4, 5, 100.1, 6.6, 99.3, 7.8,
  98.6, 8.2, 98.4, 9.8, 98.7, 11, 98.5, 13, 97.7, 16.5, 96.9, 17,
  96.2, 16.7, 94.5, 16.2, 94.2, 18.5, 93.3, 19.5, 92.3, 20.9, 91.8, 22.2,
  90.6, 22.7, 89.5, 21.9, 88, 21.7, 87, 21, 86.5, 19.8, 84.8, 19,
  83, 17.5, 81.5, 16.2, 80.3, 15.2, 80.1, 13.4, 79.8, 11.5, 79.2, 10,
  78.2, 8.9, 77.5, 8.1, 76.5, 9.5, 75.6, 11.8, 74.8, 13, 74, 15,
  73.2, 17.5, 72.8, 19.1, 72.7, 21, 72.2, 21.6, 70.4, 20.9, 69, 22.3,
  70, 23, 68.6, 23.5, 67.3, 24.8, 66.7, 25.4, 64, 25.2, 61.5, 25.2,
  59, 25.5, 57.3, 25.8, 56.5, 27.1, 54.5, 26.7, 52.5, 27.5, 50.8, 29,
  50.2, 30.2, 48.9, 30.2, 48.3, 29.5, 48.7, 28.5, 50, 26.8, 50.2, 26.1,
  51.2, 26.1, 51.6, 25, 52.6, 24.2, 54.4, 24.3, 55.5, 25.4, 56.3, 26.2,
  56.4, 24.9, 57.7, 23.8, 58.8, 23.5, 59.8, 22.5, 58.8, 20.5, 57.8, 19,
  56.5, 18.2, 55, 17, 52, 16, 50, 15.2, 48.5, 14, 45, 12.8, 43.5, 12.7,
  43, 14, 42.7, 16, 41.3, 18.5, 40.5, 19.8, 39.2, 21.5, 38.7, 23,
  37.2, 25.5, 35.5, 27.8, 34.9, 29.5, 34.3, 27.8, 33.6, 28.4, 32.8, 29.7,
  32.6, 29.95, 32.3, 31.2, 34.2, 31.3, 34.5, 31.7, 34.8, 32.3, 35, 33,
  35.5, 33.9, 35.8, 34.8, 35.9, 35.8, 35.8, 36.2, 36.2, 36.6, 35.8, 36.8,
  35, 36.6, 34.6, 36.8, 33.5, 36.2, 32.5, 36.1, 32, 36.5, 30.7, 36.85,
  30.2, 36.3, 29.6, 36.2, 29, 36.6, 28.2, 36.8, 27.4, 37, 27.2, 37.8,
  26.4, 38.3, 26.8, 39, 26.7, 39.3, 26.1, 39.5, 26.2, 40, 26.7, 40.4,
  27.9, 40.4, 29, 40.4, 29.4, 40.7, 29.9, 40.8, 29, 41, 29.1, 41.25,
  30.5, 41.2, 31.8, 41.45, 33.3, 42, 35, 42.1, 36, 41.7, 36.3, 41.3,
  38, 41, 39.7, 41, 41.6, 41.5, 41.4, 42.6, 40, 43.6, 42, 43.2,
  45, 42.3, 47.5, 43, 47.5, 45.5, 49, 46.5, 51, 47, 50.5, 48,
  51.5, 49.5, 55, 50.5, 61, 51, 59.5, 55, 60, 62,
];

const List<double> _auF = [
  113.5, -22, 114.2, -26, 115, -34, 118, -35, 123.5, -33.8, 129, -31.7, //
  132, -31.5, 135.5, -34.8, 138, -35.5, 140, -38, 144, -38.4, 146.5, -39,
  150, -37.5, 153, -31, 153.5, -26, 150, -22.5, 146, -19, 145.3, -15,
  143.5, -13.5, 142.5, -10.7, 141.5, -13, 141.5, -17, 139, -17.5, 136.5, -15.5,
  137, -12, 135, -12, 132, -11.3, 130, -12.5, 129.5, -15, 125, -14.5,
  123, -17, 121, -19.5, 116.5, -20.7,
];
const List<double> _tasF = [145, -41, 148, -41, 147, -43.5, 145.5, -42.8];
const List<double> _nz1F = [
  173,
  -34.5,
  175,
  -37,
  178,
  -37.7,
  176,
  -40.5,
  174.8,
  -41.3,
  174.7,
  -39.5,
  173.7,
  -38.5,
];
const List<double> _nz2F = [
  172.7,
  -40.5,
  174,
  -41.7,
  172,
  -43.5,
  170.5,
  -46,
  166.5,
  -46,
  168,
  -44,
  171,
  -42,
];
const List<double> _pngF = [
  131, -0.8, 134, -0.9, 137.5, -1.5, 141, -2.6, 145, -4.5, 147.5, -6.5, //
  150.5, -10.5, 147, -10, 143.5, -8.5, 141, -9, 138, -8.3, 138, -6,
  135, -4.2, 132.5, -3.2,
];
const List<double> _sumF = [
  95.3,
  5.5,
  98,
  4,
  100.5,
  2,
  104,
  -1.5,
  106,
  -3.2,
  105.8,
  -5.8,
  102,
  -4,
  98.5,
  0.5,
  95.5,
  3,
];
const List<double> _borF = [
  109,
  1.5,
  111,
  1.8,
  113,
  3.3,
  116,
  6.8,
  119,
  5,
  117.8,
  1,
  116.5,
  -2,
  116,
  -3.8,
  114.5,
  -4,
  111,
  -3,
  110,
  -1.5,
  109,
  0,
];
const List<double> _javF = [
  105.2,
  -6.8,
  108,
  -6.3,
  111,
  -6.5,
  114.5,
  -7.8,
  114.5,
  -8.7,
  108,
  -7.8,
  106,
  -7,
];
const List<double> _sriF = [79.8, 9.5, 81.8, 7.5, 81.3, 6, 80, 6, 79.8, 8];
const List<double> _lucF = [
  120.5,
  18.5,
  122.3,
  18.3,
  122,
  14.5,
  124,
  13,
  121.5,
  13.5,
  120.6,
  14.3,
];
const List<double> _sakF = [142, 54, 143, 53, 143.4, 49, 142.2, 46, 142, 50];
const List<double> _honF = [
  130.9,
  34,
  132,
  35.5,
  135.5,
  35.6,
  137,
  37,
  139.5,
  38,
  140,
  40.5,
  141.5,
  41.2, //
  141.8,
  39,
  141,
  37,
  140.8,
  35.6,
  139.8,
  35,
  137.3,
  34.6,
  135.8,
  33.5,
  134.5,
  34,
];
const List<double> _hokF = [
  140,
  42,
  141.5,
  45.4,
  145.5,
  43.3,
  143,
  42,
  141,
  41.8,
];
const List<double> _kyuF = [
  130,
  33.5,
  131.8,
  33.2,
  131.5,
  31.2,
  130.2,
  31.2,
  129.8,
  32.6,
];
const List<double> _mgF = [
  49.3,
  -12,
  50.4,
  -15.5,
  49.5,
  -18,
  47.5,
  -24.5,
  45,
  -25.5,
  43.7,
  -23.5,
  43.3,
  -21,
  44.4,
  -16.3,
  47,
  -15,
  48.4,
  -13.2,
];
const List<double> _ukF = [
  -5,
  50,
  1.4,
  51.2,
  1.7,
  52.7,
  0,
  53.5,
  -1.5,
  55,
  -2,
  56,
  -3,
  56,
  -1.8,
  57.5, //
  -3.5, 57.7, -5, 58.6, -6, 57.5, -5.5, 56.3, -4.8, 55.2, -3, 54.8, -3.2, 53.4,
  -4.5, 53.3, -4.2, 52.3, -5.2, 51.7, -3, 51.4, -4.5, 50.4,
];
const List<double> _ieF = [
  -6,
  52.2,
  -6,
  54,
  -5.5,
  54.5,
  -7.5,
  55.3,
  -10,
  54,
  -10,
  51.8,
  -8,
  51.6,
];
const List<double> _icF = [
  -24,
  65.5,
  -22,
  66.4,
  -16,
  66.5,
  -13.5,
  65,
  -18,
  63.4,
  -22.5,
  63.8,
];
const List<double> _sicF = [12.4, 38.1, 15.6, 38.2, 15.1, 36.7, 12.5, 37.7];
const List<double> _sarF = [8.2, 41, 9.7, 41.1, 9.6, 39.2, 8.5, 38.9, 8.4, 40];
const List<double> _corF = [8.6, 42.4, 9.4, 43, 9.5, 41.6];
const List<double> _creF = [23.5, 35.5, 26.3, 35.3, 24.5, 34.9, 23.5, 35.3];
const List<double> _anF = [
  -180,
  -78,
  -155,
  -78,
  -135,
  -74.5,
  -115,
  -74,
  -100,
  -72.5,
  -85,
  -73,
  -75,
  -72, //
  -69, -71, -67, -67.5, -62, -64.5, -57, -63.2, -61, -66, -63, -69, -60, -72,
  -62, -75, -50, -78, -35, -79, -25, -76, -15, -71, 0, -70, 15, -70,
  30, -69.5, 45, -67, 60, -67, 70, -68, 75, -69.5, 90, -66, 110, -66.3,
  130,
  -66,
  145,
  -67.5,
  160,
  -70,
  170,
  -72,
  165,
  -77,
  180,
  -78,
  180,
  -90,
  -180,
  -90,
];
const List<double> _casF = [
  47.5, 45, 49, 46.3, 51, 47, 53, 46.5, 53, 45, 51, 44.5, 50.5, 43, //
  52.8, 41.8, 53, 40, 53.8, 37.2, 54, 37, 51, 36.7, 49, 37.5, 49, 39.5,
  49.5, 40.3, 48.5, 41.8, 47.3, 43.2, 47.5, 44.3,
];

const Color _cNA = WbArtColors.orange;
const Color _cSA = WbArtColors.green;
const Color _cEU = WbArtColors.blue;
const Color _cAF = WbArtColors.yellow;
const Color _cAS = WbArtColors.red;
const Color _cOC = WbArtColors.purple;
const Color _cAN = WbArtColors.teal;

const List<_Land> _worldLand = [
  _Land(_naF, _cNA),
  _Land(_glF, _cNA),
  _Land(_baffinF, _cNA),
  _Land(_victoriaF, _cNA), //
  _Land(_ellesF, _cNA), _Land(_cubaF, _cNA), _Land(_hispF, _cNA),
  _Land(_saF, _cSA),
  _Land(_euF, _cEU), _Land(_ukF, _cEU), _Land(_ieF, _cEU), _Land(_icF, _cEU),
  _Land(_sicF, _cEU),
  _Land(_sarF, _cEU),
  _Land(_corF, _cEU),
  _Land(_creF, _cEU),
  _Land(_afF, _cAF), _Land(_mgF, _cAF),
  _Land(_asF, _cAS), _Land(_honF, _cAS), _Land(_hokF, _cAS), _Land(_kyuF, _cAS),
  _Land(_sakF, _cAS),
  _Land(_sriF, _cAS),
  _Land(_lucF, _cAS),
  _Land(_sumF, _cAS),
  _Land(_borF, _cAS), _Land(_javF, _cAS), _Land(_cyF, _cAS),
  _Land(_auF, _cOC), _Land(_tasF, _cOC), _Land(_nz1F, _cOC), _Land(_nz2F, _cOC),
  _Land(_pngF, _cOC),
  _Land(_anF, _cAN),
];

// --------------------------- ORTAK YARDIMCILAR ------------------------------

void _drawLands(
  Canvas cv,
  WbArtPen pen,
  _Pr pr, {
  Color? uni,
  double alpha = 0.22,
  double line = 0.6,
}) {
  for (final l in _worldLand) {
    final path = _pp(l.p, pr);
    cv.drawPath(path, pen.fill(uni ?? l.c, alpha));
    cv.drawPath(path, pen.thin(line));
  }
  final cas = _pp(_casF, pr);
  cv.drawPath(cas, pen.fill(WbArtColors.lightBlue, 0.55));
  cv.drawPath(cas, pen.stroke(WbArtColors.blue, 0.35));
}

Path _landUnion(_Pr pr) {
  final p = Path();
  for (final l in _worldLand) {
    p.addPath(_pp(l.p, pr), Offset.zero);
  }
  return p;
}

void _frame(Canvas cv, WbArtPen pen, double w, double h, {bool sea = true}) {
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, w, h),
    const Radius.circular(4),
  );
  if (sea) cv.drawRRect(r, pen.fill(WbArtColors.lightBlue, 0.1));
  cv.drawRRect(r, pen.thin(0.6));
}

/// Bölgesel harita: kıyıları çizer (çerçeve ve kırpma ile).
void _regionMap(
  Canvas cv,
  WbArtPen pen,
  double w,
  double h,
  _Pr pr, {
  Color? uni,
  double alpha = 0.2,
}) {
  _frame(cv, pen, w, h);
  cv.save();
  cv.clipRect(Rect.fromLTWH(0, 0, w, h));
  _drawLands(cv, pen, pr, uni: uni, alpha: alpha, line: 0.6);
  cv.restore();
}

/// Türkiye'yi verilen izdüşümde vurgulu çizer.
void _trOn(Canvas cv, WbArtPen pen, _Pr pr, Color col, {double alpha = 0.4}) {
  for (final f in [_thrF, _anaF, _cyF]) {
    final p = _pp(f, pr);
    cv.drawPath(p, pen.fill(col, alpha));
    cv.drawPath(p, pen.stroke(col, 0.7));
  }
}

void _dot(Canvas cv, WbArtPen pen, Offset o, {double r = 1.8, Color? col}) {
  cv.drawCircle(o, r, pen.fill(col ?? pen.color));
}

void _plabel(
  Canvas cv,
  WbArtPen pen,
  Offset o,
  String s,
  String a, {
  double size = 6.5,
  Color? col,
  bool bold = false,
}) {
  Offset at;
  switch (a) {
    case 'left':
      at = o + const Offset(3, 0);
      break;
    case 'right':
      at = o + const Offset(-3, 0);
      break;
    case 'top':
      at = o + const Offset(0, 3);
      break;
    case 'bottom':
      at = o + const Offset(0, -3);
      break;
    default:
      at = o;
  }
  pen.text(cv, s, at, size: size, c: col, bold: bold, anchor: a);
}

void _lbl(
  Canvas cv,
  WbArtPen pen,
  _Pr pr,
  String s,
  double lon,
  double lat, {
  double size = 7,
  Color? col,
  bool bold = false,
}) {
  pen.text(cv, s, pr(lon, lat), size: size, c: col, bold: bold);
}

void _box(
  Canvas cv,
  WbArtPen pen,
  Rect r,
  String t,
  Color col, {
  double size = 8,
  bool bold = true,
  double alpha = 0.22,
}) {
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
  cv.drawRRect(rr, pen.fill(col, alpha));
  cv.drawRRect(rr, pen.stroke(col, 0.6));
  pen.text(cv, t, r.center, size: size, bold: bold);
}

List<Offset> _starPts(Offset c, double r, [double inner = 0.42]) => [
  for (int i = 0; i < 10; i++)
    Offset(
      c.dx +
          (i.isEven ? r : r * inner) * math.cos(-math.pi / 2 + i * math.pi / 5),
      c.dy +
          (i.isEven ? r : r * inner) * math.sin(-math.pi / 2 + i * math.pi / 5),
    ),
];

void _mtn(Canvas cv, WbArtPen pen, Offset o, {double s = 4, Color? col}) {
  final p = Path()
    ..moveTo(o.dx, o.dy - s)
    ..lineTo(o.dx - s * 0.9, o.dy + s * 0.6)
    ..lineTo(o.dx + s * 0.9, o.dy + s * 0.6)
    ..close();
  cv.drawPath(p, pen.fill(col ?? WbArtColors.brown, 0.8));
}

void _ridge(
  Canvas cv,
  WbArtPen pen,
  List<double> f,
  _Pr pr, {
  double gap = 7,
  double s = 2.6,
}) {
  final pts = _pts(f, pr);
  for (int i = 0; i + 1 < pts.length; i++) {
    final a = pts[i];
    final b = pts[i + 1];
    final len = (b - a).distance;
    if (len == 0) continue;
    double t = 0;
    while (t <= len) {
      _mtn(cv, pen, a + (b - a) * (t / len), s: s);
      t += gap;
    }
  }
}

// --------------------------- KÜRE (ORTOGRAFİK) ------------------------------

double _cosc(double lon, double lat, double lon0, double lat0) {
  final l = (lon - lon0) * math.pi / 180;
  final p = lat * math.pi / 180;
  final p0 = lat0 * math.pi / 180;
  return math.sin(p0) * math.sin(p) + math.cos(p0) * math.cos(p) * math.cos(l);
}

Offset _orth(
  double lon,
  double lat,
  double lon0,
  double lat0,
  double r,
  Offset ctr,
) {
  final l = (lon - lon0) * math.pi / 180;
  final p = lat * math.pi / 180;
  final p0 = lat0 * math.pi / 180;
  double x = math.cos(p) * math.sin(l);
  double y =
      math.cos(p0) * math.sin(p) - math.sin(p0) * math.cos(p) * math.cos(l);
  if (_cosc(lon, lat, lon0, lat0) < 0) {
    final d = math.sqrt(x * x + y * y);
    if (d > 1e-6) {
      x /= d;
      y /= d;
    } else {
      x = 1;
      y = 0;
    }
  }
  return Offset(ctr.dx + r * x, ctr.dy - r * y);
}

void _gline(
  Canvas cv,
  Paint p,
  List<List<double>> pts,
  double lon0,
  double lat0,
  double r,
  Offset ctr,
) {
  final path = Path();
  bool down = false;
  for (final q in pts) {
    if (_cosc(q[0], q[1], lon0, lat0) >= 0) {
      final o = _orth(q[0], q[1], lon0, lat0, r, ctr);
      if (!down) {
        path.moveTo(o.dx, o.dy);
        down = true;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    } else {
      down = false;
    }
  }
  cv.drawPath(path, p);
}

List<List<double>> _parallel(double lat) => [
  for (double lon = -180; lon <= 180; lon += 3) [lon, lat],
];
List<List<double>> _meridian(double lon) => [
  for (double lat = -90; lat <= 90; lat += 3) [lon, lat],
];

void _globe(
  Canvas cv,
  WbArtPen pen,
  Offset ctr,
  double r,
  double lon0,
  double lat0, {
  double step = 30,
}) {
  cv.drawCircle(ctr, r, pen.fill(WbArtColors.lightBlue, 0.14));
  cv.save();
  cv.clipPath(Path()..addOval(Rect.fromCircle(center: ctr, radius: r)));
  Offset pr(double lon, double lat) => _orth(lon, lat, lon0, lat0, r, ctr);
  for (final l in _worldLand) {
    if (identical(l.p, _anF) && lat0.abs() < 5) {
      continue;
    }
    cv.drawPath(_pp(l.p, pr), pen.fill(l.c, 0.35));
  }
  cv.restore();
  final gp = pen.thin(0.3);
  for (double lon = -180; lon < 180; lon += step) {
    _gline(cv, gp, _meridian(lon), lon0, lat0, r, ctr);
  }
  for (double lat = -60; lat <= 60; lat += step) {
    _gline(cv, gp, _parallel(lat), lon0, lat0, r, ctr);
  }
  cv.drawCircle(ctr, r, pen.line);
}

// --------------------------- TÜRKİYE TEMEL ÇİZİM ----------------------------

Path _trLand() {
  final p = Path();
  p.addPath(_pp(_thrF, _tr), Offset.zero);
  p.addPath(_pp(_anaF, _tr), Offset.zero);
  return p;
}

void _trBase(Canvas cv, WbArtPen pen, {Color? fillC, double alpha = 0.18}) {
  final col = fillC ?? WbArtColors.green;
  for (final f in [_thrF, _anaF, _cyF]) {
    final p = _pp(f, _tr);
    cv.drawPath(p, pen.fill(col, alpha));
    cv.drawPath(p, pen.line);
  }
}

void _seaLabel(
  Canvas cv,
  WbArtPen pen,
  String s,
  double lon,
  double lat, {
  double size = 7,
}) {
  pen.text(cv, s, _tr(lon, lat), size: size, c: WbArtColors.blue);
}

// --------------------------- TÜRKİYE VERİLERİ -------------------------------

const List<_Pt> _cities = [
  _Pt('İstanbul', 28.98, 41.01, 'right'),
  _Pt('Edirne', 26.56, 41.67, 'left'),
  _Pt('Çanakkale', 26.4, 40.15, 'bottom'),
  _Pt('Bursa', 29.06, 40.18, 'left'),
  _Pt('Balıkesir', 27.89, 39.65, 'right'),
  _Pt('İzmir', 27.14, 38.42, 'right'),
  _Pt('Muğla', 28.36, 37.21, 'right'),
  _Pt('Denizli', 29.09, 37.77, 'left'),
  _Pt('Antalya', 30.7, 36.9, 'top'),
  _Pt('Eskişehir', 30.52, 39.78, 'left'),
  _Pt('Ankara', 32.85, 39.93, 'left'),
  _Pt('Konya', 32.48, 37.87, 'left'),
  _Pt('Zonguldak', 31.8, 41.45, 'top'),
  _Pt('Sinop', 35.15, 42.03, 'top'),
  _Pt('Samsun', 36.33, 41.29, 'top'),
  _Pt('Trabzon', 39.72, 41.0, 'top'),
  _Pt('Kayseri', 35.49, 38.72, 'left'),
  _Pt('Sivas', 37.02, 39.75, 'left'),
  _Pt('Erzurum', 41.27, 39.9, 'left'),
  _Pt('Kars', 43.1, 40.6, 'right'),
  _Pt('Van', 43.4, 38.5, 'left'),
  _Pt('Malatya', 38.31, 38.35, 'top'),
  _Pt('Diyarbakır', 40.22, 37.91, 'left'),
  _Pt('Şanlıurfa', 38.79, 37.16, 'bottom'),
  _Pt('Gaziantep', 37.38, 37.07, 'top'),
  _Pt('Adana', 35.32, 37.0, 'left'),
  _Pt('Mersin', 34.64, 36.8, 'right'),
  _Pt('Hatay', 36.16, 36.2, 'left'),
];

const List<_Reg> _regions = [
  _Reg(
    'Marmara',
    WbArtColors.blue,
    [
      25,
      43,
      30.9,
      43,
      30.7,
      40.3,
      29.8,
      39.8,
      28.3,
      39.5,
      27.5,
      39.3,
      26.5,
      39.4,
      25,
      39.3,
    ],
    28.0,
    40.0,
  ),
  _Reg(
    'Ege',
    WbArtColors.green,
    [
      25,
      39.3,
      26.5,
      39.4,
      27.5,
      39.3,
      28.3,
      39.5,
      29.8,
      39.8,
      31.2,
      39.6,
      31.0,
      38.2,
      30.2,
      37.5, //
      29.5, 36.9, 29.2, 36.4, 28, 35, 25, 35,
    ],
    28.2,
    38.4,
  ),
  _Reg(
    'Akdeniz',
    WbArtColors.orange,
    [
      28,
      35,
      29.2,
      36.4,
      29.5,
      36.9,
      30.2,
      37.5,
      31.2,
      37.6,
      32.5,
      37.2,
      33.8,
      37.2,
      35.2,
      37.9, //
      36.8, 38.3, 37.5, 38.0, 37.4, 36.6, 37.5, 35,
    ],
    34.2,
    36.95,
  ),
  _Reg(
    'İç Anadolu',
    WbArtColors.yellow,
    [
      31.2,
      39.6,
      30.8,
      40.3,
      31.8,
      40.5,
      32.8,
      40.8,
      33.8,
      41.1,
      34.8,
      40.8,
      35.8,
      40.4,
      36.8,
      40.4, //
      37.8,
      40.3,
      38.6,
      40.0,
      38.7,
      39.4,
      38.5,
      38.8,
      38.3,
      38.2,
      37.5,
      38.0,
      36.8,
      38.3,
      35.2,
      37.9,
      33.8, 37.2, 32.5, 37.2, 31.2, 37.6, 30.2, 37.5, 31.0, 38.2,
    ],
    33.2,
    39.2,
  ),
  _Reg(
    'Karadeniz',
    WbArtColors.teal,
    [
      30.9,
      43,
      30.7,
      40.3,
      30.8,
      40.3,
      31.8,
      40.5,
      32.8,
      40.8,
      33.8,
      41.1,
      34.8,
      40.8,
      35.8,
      40.4, //
      36.8,
      40.4,
      37.8,
      40.3,
      38.6,
      40.0,
      39.5,
      40.4,
      40.3,
      40.4,
      41.2,
      40.5,
      41.7,
      41.0,
      42.7,
      41.4,
      43,
      43,
    ],
    36.0,
    41.0,
  ),
  _Reg(
    'Doğu Anadolu',
    WbArtColors.purple,
    [
      38.6,
      40.0,
      38.7,
      39.4,
      38.5,
      38.8,
      38.3,
      38.2,
      39.5,
      38.3,
      40.5,
      38.4,
      41.5,
      38.3,
      42.2,
      38.0, //
      42.9,
      37.8,
      43.2,
      37.35,
      46,
      37.0,
      46,
      41.5,
      42.7,
      41.4,
      41.7,
      41.0,
      41.2,
      40.5,
      40.3,
      40.4,
      39.5, 40.4,
    ],
    41.6,
    39.3,
  ),
  _Reg(
    'Güneydoğu\nAnadolu',
    WbArtColors.red,
    [
      37.5,
      38.0,
      38.3,
      38.2,
      39.5,
      38.3,
      40.5,
      38.4,
      41.5,
      38.3,
      42.2,
      38.0,
      42.9,
      37.8,
      43.2,
      37.35, //
      43.6, 37.2, 43.6, 36, 37.5, 36,
    ],
    40.0,
    37.3,
  ),
];

const List<_Reg> _climates = [
  _Reg('Karasal', WbArtColors.yellow, [24, 44, 47, 44, 47, 34, 24, 34], 0, 0),
  _Reg(
    'Sert karasal',
    WbArtColors.purple,
    [
      38.5,
      40.4,
      39.5,
      40.4,
      41.0,
      40.5,
      42.0,
      41.1,
      46,
      41.6,
      46,
      37.0,
      43,
      37.5,
      41.5,
      38.2,
      40,
      38.3, //
      38.6, 38.5,
    ],
    0,
    0,
  ),
  _Reg(
    'Akdeniz',
    WbArtColors.orange,
    [
      25,
      39.7,
      27,
      39.3,
      28.5,
      38.7,
      29.5,
      37.7,
      31,
      37.2,
      33,
      37.0,
      34.5,
      37.3,
      35.8,
      37.6,
      37,
      37.3, //
      37.3, 36.5, 37.3, 35, 25, 35,
    ],
    0,
    0,
  ),
  _Reg(
    'Karadeniz',
    WbArtColors.green,
    [
      30,
      43,
      30.3,
      41.1,
      31.5,
      40.6,
      33.5,
      41.2,
      35,
      40.8,
      36.5,
      40.4,
      38,
      40.3,
      39.5,
      40.4,
      41,
      40.5, //
      42, 41.1, 43, 43,
    ],
    0,
    0,
  ),
  _Reg(
    'Marmara',
    WbArtColors.blue,
    [
      25,
      43,
      30.3,
      43,
      30.3,
      41.1,
      29.8,
      40.3,
      28.5,
      39.9,
      27.5,
      39.6,
      26.8,
      39.7,
      25,
      39.7,
    ],
    0,
    0,
  ),
];

// -------------------------------- ŞEKİLLER ----------------------------------

final List<WbArtItem> wbArtSocial = [
  // ------------------------------- TÜRKİYE ---------------------------------
  WbArtItem(
    'sos_tr_bos',
    'Türkiye Boş Harita',
    320,
    176,
    (cv, pen) {
      _trBase(cv, pen);
    },
    tags: 'türkiye harita boş konturlu kontur anadolu trakya coğrafya sınır',
  ),
  WbArtItem(
    'sos_tr_sehir',
    'Türkiye Şehirler',
    320,
    176,
    (cv, pen) {
      _trBase(cv, pen, alpha: 0.12);
      for (final c in _cities) {
        final o = _tr(c.lon, c.lat);
        if (c.n == 'Ankara') {
          cv.drawPath(
            WbArtPen.poly(_starPts(o, 4.2)),
            pen.fill(WbArtColors.red),
          );
        } else {
          _dot(cv, pen, o, r: 1.8);
        }
        _plabel(
          cv,
          pen,
          o,
          c.n,
          c.a,
          bold: c.n == 'Ankara' || c.n == 'İstanbul',
        );
      }
    },
    tags:
        'türkiye şehirler iller büyük şehir başkent ankara istanbul izmir harita',
  ),
  WbArtItem(
    'sos_tr_bolge',
    'Türkiye Bölgeleri',
    320,
    176,
    (cv, pen) {
      cv.save();
      cv.clipPath(_trLand());
      for (final r in _regions) {
        cv.drawPath(_pp(r.poly, _tr), pen.fill(r.color, 0.3));
        cv.drawPath(_pp(r.poly, _tr), pen.stroke(r.color, 0.35));
      }
      cv.restore();
      cv.drawPath(_pp(_cyF, _tr), pen.fill(WbArtColors.gray, 0.2));
      _trBase(cv, pen, alpha: 0);
      for (final r in _regions) {
        pen.text(cv, r.name, _tr(r.lon, r.lat), size: 7.5, bold: true);
      }
    },
    tags:
        'türkiye bölgeleri yedi coğrafi bölge marmara ege akdeniz karadeniz iç anadolu doğu güneydoğu harita',
  ),
  WbArtItem(
    'sos_tr_dag_nehir',
    'Türkiye Dağlar ve Nehirler',
    320,
    176,
    (cv, pen) {
      _trBase(cv, pen, alpha: 0.1);
      final blue = pen.stroke(WbArtColors.blue, 0.8);
      const rivers = <List<double>>[
        [
          37.8,
          39.7,
          36.8,
          39.4,
          35.5,
          39.3,
          34.0,
          39.5,
          33.5,
          39.8,
          34.0,
          40.3,
          34.8,
          40.9,
          35.5,
          41.3,
          35.95,
          41.65,
        ],
        [
          41.3,
          39.9,
          40.5,
          39.6,
          39.6,
          39.0,
          38.8,
          38.8,
          38.4,
          38.2,
          37.9,
          37.5,
          38.0,
          37.1,
          38.0,
          36.8,
        ],
        [
          39.45,
          38.5,
          40.1,
          38.2,
          40.25,
          37.9,
          41.0,
          37.8,
          41.6,
          37.5,
          42.2,
          37.3,
        ],
        [
          31.0,
          39.4,
          31.6,
          39.7,
          31.4,
          40.2,
          30.8,
          40.5,
          30.6,
          40.9,
          30.65,
          41.1,
        ],
        [30.15, 38.07, 29.2, 37.95, 28.5, 37.85, 27.85, 37.8, 27.2, 37.7],
        [
          40.8,
          39.7,
          41.5,
          40.0,
          42.2,
          40.2,
          43.1,
          40.3,
          43.6,
          40.15,
          44.1,
          40.0,
          44.8,
          39.7,
        ],
      ];
      for (final r in rivers) {
        cv.drawPath(_pl(r, _tr), blue);
      }
      // Göller
      for (final g in const [
        [42.85, 38.6, 0.5, 0.25],
        [33.4, 38.75, 0.4, 0.3],
        [31.5, 37.75, 0.12, 0.4],
        [30.9, 37.9, 0.1, 0.2],
      ]) {
        final rect = Rect.fromCenter(
          center: _tr(g[0], g[1]),
          width: g[2] * 2 * 15.238,
          height: g[3] * 2 * 19.55,
        );
        cv.drawOval(rect, pen.fill(WbArtColors.lightBlue, 0.7));
        cv.drawOval(rect, pen.stroke(WbArtColors.blue, 0.4));
      }
      // Sıradağlar
      _ridge(cv, pen, const [
        29.8,
        37.0,
        31.5,
        37.0,
        33.0,
        36.9,
        34.5,
        37.3,
        36.0,
        37.6,
      ], _tr);
      _ridge(cv, pen, const [
        31.0,
        41.0,
        33.0,
        41.2,
        35.0,
        41.0,
        37.0,
        40.7,
        38.5,
        40.6,
      ], _tr);
      _ridge(cv, pen, const [38.5, 40.6, 40.0, 40.7, 41.2, 40.9], _tr);
      for (final m in const [
        _Pt('Ağrı Dağı', 44.3, 39.7, 'bottom'),
        _Pt('Erciyes', 35.45, 38.53, 'top'),
        _Pt('Uludağ', 29.1, 40.07, 'top'),
        _Pt('Kaçkar', 41.15, 40.83, 'bottom'),
        _Pt('Hasan D.', 34.17, 38.13, 'top'),
        _Pt('Süphan', 42.83, 38.93, 'bottom'),
      ]) {
        final o = _tr(m.lon, m.lat);
        _mtn(cv, pen, o, s: 5, col: WbArtColors.red);
        _plabel(
          cv,
          pen,
          o,
          m.n,
          m.a,
          size: 6.5,
          col: WbArtColors.brown,
          bold: true,
        );
      }
      pen.text(
        cv,
        'Toros Dağları',
        _tr(32.2, 36.45),
        size: 6.5,
        c: WbArtColors.brown,
        bold: true,
      );
      pen.text(
        cv,
        'Kuzey Anadolu (Karadeniz) Dağları',
        _tr(35.5, 41.55),
        size: 6,
        c: WbArtColors.brown,
      );
      final bl = WbArtColors.blue;
      pen.text(cv, 'Kızılırmak', _tr(34.5, 39.2), size: 6.5, c: bl, bold: true);
      pen.text(cv, 'Fırat', _tr(39.5, 39.35), size: 6.5, c: bl, bold: true);
      pen.text(cv, 'Dicle', _tr(41.1, 37.55), size: 6.5, c: bl, bold: true);
      pen.text(cv, 'Sakarya', _tr(31.9, 40.0), size: 6.5, c: bl, bold: true);
      pen.text(cv, 'B. Menderes', _tr(28.6, 38.2), size: 6, c: bl, bold: true);
      pen.text(cv, 'Aras', _tr(42.5, 40.45), size: 6.5, c: bl, bold: true);
      pen.text(cv, 'Van Gölü', _tr(42.85, 38.1), size: 6, c: bl);
      pen.text(cv, 'Tuz Gölü', _tr(33.4, 38.3), size: 6, c: bl);
      // Anahtar
      _mtn(cv, pen, const Offset(8, 165), s: 4, col: WbArtColors.red);
      pen.text(
        cv,
        'Dağ/zirve',
        const Offset(14, 165),
        size: 6.5,
        anchor: 'left',
      );
      cv.drawLine(const Offset(58, 165), const Offset(72, 165), blue);
      pen.text(cv, 'Nehir', const Offset(76, 165), size: 6.5, anchor: 'left');
    },
    tags:
        'türkiye dağlar nehirler kızılırmak fırat dicle sakarya menderes ağrı erciyes uludağ toros kaçkar harita fiziki',
  ),
  WbArtItem(
    'sos_tr_iklim',
    'Türkiye İklim Bölgeleri',
    320,
    190,
    (cv, pen) {
      cv.save();
      cv.clipPath(_trLand());
      for (final r in _climates) {
        cv.drawPath(
          _pp(r.poly, _tr),
          pen.fill(r.color, r.name == 'Karasal' ? 0.25 : 0.4),
        );
      }
      cv.restore();
      cv.drawPath(_pp(_cyF, _tr), pen.fill(WbArtColors.orange, 0.4));
      _trBase(cv, pen, alpha: 0);
      pen.text(cv, 'Akdeniz\niklimi', _tr(31.5, 36.9), size: 7, bold: true);
      pen.text(cv, 'Karadeniz\niklimi', _tr(35.5, 41.35), size: 7, bold: true);
      pen.text(
        cv,
        'Karasal iklim\n(İç Anadolu)',
        _tr(33.3, 39.0),
        size: 7,
        bold: true,
      );
      pen.text(
        cv,
        'Sert karasal\n(Doğu Anadolu)',
        _tr(41.6, 39.2),
        size: 7,
        bold: true,
      );
      pen.text(cv, 'Marmara\n(geçiş)', _tr(27.7, 40.1), size: 6.5, bold: true);
      // Anahtar
      const names = [
        'Akdeniz',
        'Karadeniz',
        'Karasal',
        'Sert karasal',
        'Marmara',
      ];
      const cols = [
        WbArtColors.orange,
        WbArtColors.green,
        WbArtColors.yellow,
        WbArtColors.purple,
        WbArtColors.blue,
      ];
      for (int i = 0; i < 5; i++) {
        final x = 6.0 + i * 63;
        cv.drawRect(Rect.fromLTWH(x, 180, 8, 6), pen.fill(cols[i], 0.6));
        pen.text(cv, names[i], Offset(x + 11, 183), size: 6.5, anchor: 'left');
      }
    },
    tags:
        'türkiye iklim bölgeleri akdeniz karadeniz karasal sert karasal marmara iklim haritası',
  ),
  WbArtItem(
    'sos_tr_komsu',
    'Türkiye Komşuları',
    320,
    176,
    (cv, pen) {
      _trBase(cv, pen, alpha: 0.15);
      pen.text(cv, 'TÜRKİYE', _tr(35.5, 39.4), size: 11, bold: true);
      final red = WbArtColors.red;
      void nb(String n, double lon, double lat, double tlon, double tlat) {
        final from = _tr(lon, lat);
        final to = _tr(tlon, tlat);
        pen.text(cv, n, from, size: 7.5, c: red, bold: true);
        final d = (to - from);
        final u = d / d.distance;
        pen.arrow(cv, from + u * 8, to, c: red, size: 5);
      }

      nb('Yunanistan', 25.4, 42.5, 26.25, 41.4);
      nb('Bulgaristan', 28.0, 43.0, 27.4, 42.1);
      nb('Gürcistan', 41.6, 42.8, 41.9, 41.55);
      nb('Ermenistan', 44.9, 41.6, 43.9, 40.5);
      nb('Azerbaycan\n(Nahçıvan)', 45.2, 40.2, 44.7, 39.7);
      nb('İran', 45.4, 38.6, 44.5, 38.7);
      nb('Irak', 43.3, 35.6, 43.3, 37.2);
      nb('Suriye', 39.5, 35.4, 39.5, 36.75);
      pen.text(cv, 'Kıbrıs', _tr(33.4, 34.7), size: 7, bold: true);
      _seaLabel(cv, pen, 'Karadeniz', 34, 42.9, size: 8);
      _seaLabel(cv, pen, 'Ege\nDenizi', 25.4, 38.4);
      _seaLabel(cv, pen, 'Akdeniz', 31, 35.3, size: 8);
    },
    tags:
        'türkiye komşuları komşu ülkeler yunanistan bulgaristan gürcistan ermenistan iran irak suriye azerbaycan harita',
  ),
  WbArtItem(
    'sos_tr_plaka',
    'Türkiye İl Plaka Kodları (1-81)',
    300,
    214,
    (cv, pen) {
      pen.text(
        cv,
        'İl Plaka Kodları',
        const Offset(150, 10),
        size: 10,
        bold: true,
      );
      const cols = [
        WbArtColors.blue,
        WbArtColors.green,
        WbArtColors.orange,
        WbArtColors.purple,
        WbArtColors.teal,
        WbArtColors.pink,
      ];
      for (int n = 1; n <= 81; n++) {
        final row = (n - 1) ~/ 9;
        final col = (n - 1) % 9;
        final r = Rect.fromLTWH(15.0 + col * 30, 22.0 + row * 20, 29, 19);
        final special = n == 6 || n == 34 || n == 35;
        final colr = cols[row % cols.length];
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
        cv.drawRRect(rr, pen.fill(colr, special ? 0.6 : 0.22));
        cv.drawRRect(rr, pen.stroke(colr, 0.5));
        pen.text(cv, '$n', r.center, size: 9, bold: true);
      }
      pen.text(
        cv,
        'Vurgulu kutular: 06, 34, 35',
        const Offset(150, 208),
        size: 6.5,
      );
    },
    tags: 'türkiye il plaka kodları 81 il plaka numarası ızgara tablo',
  ),

  // ------------------------------- DÜNYA -----------------------------------
  WbArtItem(
    'sos_dunya_bos',
    'Dünya Boş Harita',
    400,
    200,
    (cv, pen) {
      _frame(cv, pen, 400, 200, sea: false);
      _drawLands(cv, pen, _ws(1.1111), uni: pen.color, alpha: 0.12, line: 0.7);
    },
    tags: 'dünya harita boş kıtalar kara dünya haritası konturlu',
  ),
  WbArtItem(
    'sos_dunya_kita',
    'Dünya Kıtalar',
    400,
    200,
    (cv, pen) {
      final pr = _ws(1.1111);
      _frame(cv, pen, 400, 200);
      _drawLands(cv, pen, pr, alpha: 0.35, line: 0.7);
      _lbl(cv, pen, pr, 'KUZEY\nAMERİKA', -100, 45, size: 8, bold: true);
      _lbl(cv, pen, pr, 'GÜNEY\nAMERİKA', -60, -14, size: 8, bold: true);
      _lbl(cv, pen, pr, 'AVRUPA', 18, 54, size: 6.5, bold: true);
      _lbl(cv, pen, pr, 'AFRİKA', 20, 4, size: 9, bold: true);
      _lbl(cv, pen, pr, 'ASYA', 90, 48, size: 10, bold: true);
      _lbl(cv, pen, pr, 'OKYANUSYA', 134, -26, size: 7, bold: true);
      _lbl(cv, pen, pr, 'ANTARKTİKA', 20, -80, size: 8, bold: true);
    },
    tags:
        'dünya kıtalar kıta asya avrupa afrika amerika okyanusya antarktika renkli harita',
  ),
  WbArtItem(
    'sos_dunya_okyanus',
    'Dünya Okyanuslar',
    400,
    200,
    (cv, pen) {
      final pr = _ws(1.1111);
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 400, 200),
          const Radius.circular(4),
        ),
        pen.fill(WbArtColors.blue, 0.12),
      );
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 400, 200));
      _drawLands(cv, pen, pr, uni: WbArtColors.gray, alpha: 0.35, line: 0.6);
      cv.restore();
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 400, 200),
          const Radius.circular(4),
        ),
        pen.thin(0.6),
      );
      final b = WbArtColors.blue;
      _lbl(
        cv,
        pen,
        pr,
        'PASİFİK\nOKYANUSU',
        -150,
        8,
        size: 9,
        col: b,
        bold: true,
      );
      _lbl(
        cv,
        pen,
        pr,
        'PASİFİK\nOKYANUSU',
        170,
        16,
        size: 7,
        col: b,
        bold: true,
      );
      _lbl(
        cv,
        pen,
        pr,
        'ATLAS\nOKYANUSU',
        -36,
        24,
        size: 9,
        col: b,
        bold: true,
      );
      _lbl(
        cv,
        pen,
        pr,
        'ATLAS\nOKYANUSU',
        -18,
        -28,
        size: 7,
        col: b,
        bold: true,
      );
      _lbl(cv, pen, pr, 'HİNT\nOKYANUSU', 78, -18, size: 9, col: b, bold: true);
      _lbl(
        cv,
        pen,
        pr,
        'ARKTİK (KUZEY BUZ)\nOKYANUSU',
        10,
        82,
        size: 6.5,
        col: b,
        bold: true,
      );
      _lbl(
        cv,
        pen,
        pr,
        'GÜNEY (ANTARKTİKA) OKYANUSU',
        40,
        -60,
        size: 6.5,
        col: b,
        bold: true,
      );
    },
    tags: 'dünya okyanuslar pasifik atlas hint arktik büyük okyanus harita',
  ),
  WbArtItem(
    'sos_yarim_kure',
    'Yarım Küreler ve Ekvator / Başlangıç Meridyeni',
    340,
    200,
    (cv, pen) {
      final red = WbArtColors.red;
      final orange = WbArtColors.orange;
      const c1 = Offset(90, 95);
      const c2 = Offset(250, 95);
      const r = 66.0;
      _globe(cv, pen, c1, r, 20, 0);
      _globe(cv, pen, c2, r, 0, 0);
      // Ekvator
      cv.drawLine(
        const Offset(90 - r, 95),
        const Offset(90 + r, 95),
        pen.stroke(red, 1.3),
      );
      // Başlangıç meridyeni ve 180°
      cv.drawLine(
        const Offset(250, 95 - r),
        const Offset(250, 95 + r),
        pen.stroke(orange, 1.3),
      );
      pen.text(
        cv,
        'KUZEY YARIM KÜRE',
        const Offset(90, 28),
        size: 7.5,
        bold: true,
      );
      pen.text(
        cv,
        'GÜNEY YARIM KÜRE',
        const Offset(90, 164),
        size: 7.5,
        bold: true,
      );
      pen.text(
        cv,
        'Ekvator (0°)',
        const Offset(90, 95 - 7),
        size: 7,
        c: red,
        bold: true,
      );
      pen.text(
        cv,
        'BATI\nYARIM KÜRE',
        const Offset(250 - r - 2, 25),
        size: 7.5,
        bold: true,
        anchor: 'right',
      );
      pen.text(
        cv,
        'DOĞU\nYARIM KÜRE',
        const Offset(250 + r + 2, 25),
        size: 7.5,
        bold: true,
        anchor: 'left',
      );
      pen.text(
        cv,
        'Başlangıç Meridyeni (0°)',
        const Offset(250, 168),
        size: 7,
        c: orange,
        bold: true,
      );
      pen.text(
        cv,
        'Ekvator: kutuplardan eşit uzaklıktaki 0° enlem dairesi',
        const Offset(90, 182),
        size: 6.5,
      );
      pen.text(
        cv,
        'Greenwich\'ten geçen 0° boylam çizgisi',
        const Offset(250, 182),
        size: 6.5,
      );
      pen.text(cv, 'Kuzey', const Offset(90, 95 - r - 8), size: 7, bold: true);
    },
    tags:
        'yarım küreler kuzey güney doğu batı ekvator başlangıç meridyeni greenwich dünya küre',
  ),
  WbArtItem(
    'sos_enlem_boylam',
    'Enlem-Boylam (Paralel / Meridyen) Küresi',
    360,
    230,
    (cv, pen) {
      const ctr = Offset(120, 116);
      const r = 95.0;
      _globe(cv, pen, ctr, r, 20, 0, step: 30);
      final red = WbArtColors.red;
      final orange = WbArtColors.orange;
      final blue = WbArtColors.blue;
      // Başlangıç meridyeni
      _gline(
        cv,
        pen.stroke(WbArtColors.purple, 1.1),
        _meridian(0),
        20,
        0,
        r,
        ctr,
      );
      void par(double lat, Color col, String name, double wf) {
        final y = ctr.dy - r * math.sin(lat * math.pi / 180);
        final hw = r * math.cos(lat * math.pi / 180);
        cv.drawLine(
          Offset(ctr.dx - hw, y),
          Offset(ctr.dx + hw, y),
          pen.stroke(col, wf),
        );
        cv.drawLine(
          Offset(ctr.dx + hw, y),
          Offset(ctr.dx + r + 12, y),
          pen.thin(0.3),
        );
        pen.text(
          cv,
          name,
          Offset(ctr.dx + r + 14, y),
          size: 7,
          c: col,
          bold: true,
          anchor: 'left',
        );
      }

      par(66.5, blue, 'Kuzey Kutup Dairesi 66°33\'K', 0.9);
      par(23.5, orange, 'Yengeç Dönencesi 23°27\'K', 0.9);
      par(0, red, 'EKVATOR 0°', 1.4);
      par(-23.5, orange, 'Oğlak Dönencesi 23°27\'G', 0.9);
      par(-66.5, blue, 'Güney Kutup Dairesi 66°33\'G', 0.9);
      pen.text(
        cv,
        'Kuzey Kutbu 90°K',
        Offset(ctr.dx, ctr.dy - r - 8),
        size: 7.5,
        bold: true,
      );
      pen.text(
        cv,
        'Güney Kutbu 90°G',
        Offset(ctr.dx, ctr.dy + r + 9),
        size: 7.5,
        bold: true,
      );
      pen.text(
        cv,
        'Başlangıç Meridyeni 0°',
        Offset(ctr.dx + r + 14, ctr.dy + r - 2),
        size: 7,
        c: WbArtColors.purple,
        bold: true,
        anchor: 'left',
      );
      pen.text(
        cv,
        'Paralel = enlem daireleri',
        Offset(ctr.dx + r + 14, 18),
        size: 6.5,
        anchor: 'left',
      );
      pen.text(
        cv,
        'Meridyen = boylam yarım daireleri',
        Offset(ctr.dx + r + 14, 30),
        size: 6.5,
        anchor: 'left',
      );
    },
    tags:
        'enlem boylam paralel meridyen ekvator dönence yengeç oğlak kutup daireleri küre coğrafi koordinat',
  ),
  WbArtItem(
    'sos_saat_dilimi',
    'Dünya Saat Dilimleri Şeridi',
    360,
    184,
    (cv, pen) {
      Offset pr(double lon, double lat) => Offset(lon + 180, (80 - lat) + 20);
      const cols = [
        WbArtColors.blue,
        WbArtColors.green,
        WbArtColors.orange,
        WbArtColors.purple,
        WbArtColors.teal,
        WbArtColors.pink,
      ];
      for (int j = 0; j <= 24; j++) {
        final left = j == 0 ? 0.0 : (-172.5 + 15 * (j - 1)) + 180;
        final right = j == 24 ? 360.0 : (-172.5 + 15 * j) + 180;
        final r = Rect.fromLTRB(left, 20, right, 160);
        final isTr = j == 15;
        cv.drawRect(
          r,
          pen.fill(
            isTr ? WbArtColors.red : cols[j % cols.length],
            isTr ? 0.4 : 0.15,
          ),
        );
        cv.drawRect(r, pen.thin(0.3));
        final s = j == 12 ? '0' : (j > 12 ? '+${j - 12}' : '${j - 12}');
        pen.text(
          cv,
          s,
          Offset((left + right) / 2, 12),
          size: 6.5,
          bold: true,
          c: isTr ? WbArtColors.red : null,
        );
      }
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 20, 360, 140));
      for (final l in _worldLand) {
        cv.drawPath(_pp(l.p, pr), pen.fill(pen.color, 0.3));
        cv.drawPath(_pp(l.p, pr), pen.thin(0.5));
      }
      cv.restore();
      cv.drawRect(const Rect.fromLTWH(0, 20, 360, 140), pen.thin(0.6));
      pen.text(
        cv,
        'Greenwich (UTC 0)',
        const Offset(180, 168),
        size: 6.5,
        bold: true,
      );
      pen.arrow(
        cv,
        const Offset(180, 163),
        const Offset(180, 160),
        size: 3,
        line: false,
      );
      pen.text(
        cv,
        'Türkiye UTC+3',
        const Offset(195 + 15 * 3 - 60 + 40, 168),
        size: 6.5,
        c: WbArtColors.red,
        bold: true,
      );
      pen.text(
        cv,
        'Her dilim 15° boylam = 1 saat · 180°: Tarih değiştirme çizgisi',
        const Offset(180, 179),
        size: 6.5,
      );
    },
    tags: 'dünya saat dilimleri utc gmt zaman dilimi şerit türkiye yerel saat',
  ),
  WbArtItem(
    'sos_pusula',
    'Pusula Gülü (8 Yön)',
    240,
    250,
    (cv, pen) {
      const ctr = Offset(120, 122);
      final red = WbArtColors.red;
      cv.drawCircle(ctr, 92, pen.thin(0.6));
      cv.drawCircle(ctr, 80, pen.thin(0.4));
      for (int i = 0; i < 24; i++) {
        final a = i * math.pi / 12;
        final len = i % 3 == 0 ? 10.0 : 5.0;
        final p1 = ctr + Offset(math.sin(a), -math.cos(a)) * 80;
        final p2 = ctr + Offset(math.sin(a), -math.cos(a)) * (80 + len);
        cv.drawLine(p1, p2, pen.thin(0.4));
      }
      void spike(double deg, double len, double wid, Color col) {
        final a = deg * math.pi / 180;
        final dir = Offset(math.sin(a), -math.cos(a));
        final perp = Offset(math.cos(a), math.sin(a));
        final tip = ctr + dir * len;
        final p1 = ctr + perp * wid;
        final p2 = ctr - perp * wid;
        cv.drawPath(WbArtPen.poly([tip, ctr, p1]), pen.fill(col, 0.6));
        cv.drawPath(WbArtPen.poly([tip, ctr, p2]), pen.fill(col, 0.14));
        cv.drawPath(WbArtPen.poly([tip, p1, ctr, p2]), pen.thin(0.6));
      }

      for (int k = 0; k < 4; k++) {
        spike(45.0 + 90 * k, 52, 8, WbArtColors.gray);
      }
      spike(90, 76, 11, pen.color);
      spike(180, 76, 11, pen.color);
      spike(270, 76, 11, pen.color);
      spike(0, 76, 11, red);
      cv.drawCircle(ctr, 3, pen.solid);
      pen.text(
        cv,
        'K',
        ctr + const Offset(0, -104),
        size: 14,
        c: red,
        bold: true,
      );
      pen.text(cv, 'G', ctr + const Offset(0, 104), size: 14, bold: true);
      pen.text(cv, 'D', ctr + const Offset(104, 0), size: 14, bold: true);
      pen.text(cv, 'B', ctr + const Offset(-104, 0), size: 14, bold: true);
      const d = 74.0;
      pen.text(cv, 'KD', ctr + const Offset(d, -d) * 0.9, size: 8, bold: true);
      pen.text(cv, 'GD', ctr + const Offset(d, d) * 0.9, size: 8, bold: true);
      pen.text(cv, 'GB', ctr + const Offset(-d, d) * 0.9, size: 8, bold: true);
      pen.text(cv, 'KB', ctr + const Offset(-d, -d) * 0.9, size: 8, bold: true);
      pen.text(
        cv,
        'K: Kuzey   D: Doğu   G: Güney   B: Batı',
        const Offset(120, 240),
        size: 7,
      );
    },
    tags:
        'pusula gülü yön kuzey güney doğu batı kuzeydoğu 8 yön ana yönler ara yönler',
  ),
  WbArtItem(
    'sos_yon_bulma',
    'Yön Bulma (Kuzey İşareti)',
    340,
    205,
    (cv, pen) {
      final red = WbArtColors.red;
      final blue = WbArtColors.blue;
      // Sol panel: insan, üstten görünüş
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 2, 160, 200),
          const Radius.circular(5),
        ),
        pen.thin(0.5),
      );
      pen.text(cv, 'Kuzeye dön:', const Offset(82, 12), size: 7.5, bold: true);
      cv.drawCircle(const Offset(82, 112), 8, pen.fill(pen.color, 0.3));
      cv.drawCircle(const Offset(82, 112), 8, pen.thin(0.8));
      cv.drawLine(
        const Offset(62, 118),
        const Offset(102, 118),
        pen.stroke(pen.color, 1.4),
      );
      cv.drawLine(const Offset(62, 118), const Offset(62, 130), pen.line);
      cv.drawLine(const Offset(102, 118), const Offset(102, 130), pen.line);
      pen.arrow(
        cv,
        const Offset(82, 100),
        const Offset(82, 28),
        c: red,
        size: 8,
      );
      pen.text(
        cv,
        'ÖN: KUZEY (K)',
        const Offset(82, 22),
        size: 7,
        c: red,
        bold: true,
      );
      pen.arrow(
        cv,
        const Offset(110, 118),
        const Offset(150, 118),
        c: blue,
        size: 7,
      );
      pen.text(
        cv,
        'Sağ el:\nDOĞU',
        const Offset(133, 138),
        size: 7,
        c: blue,
        bold: true,
      );
      pen.arrow(
        cv,
        const Offset(54, 118),
        const Offset(14, 118),
        c: blue,
        size: 7,
      );
      pen.text(
        cv,
        'Sol el:\nBATI',
        const Offset(31, 138),
        size: 7,
        c: blue,
        bold: true,
      );
      pen.arrow(
        cv,
        const Offset(82, 136),
        const Offset(82, 180),
        c: pen.color,
        size: 7,
      );
      pen.text(
        cv,
        'ARKA: GÜNEY (G)',
        const Offset(82, 190),
        size: 7,
        bold: true,
      );
      // Sağ panel: güneş ve Kutup Yıldızı
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(178, 2, 160, 200),
          const Radius.circular(5),
        ),
        pen.thin(0.5),
      );
      pen.text(
        cv,
        'Gökyüzünden yön bulma',
        const Offset(258, 12),
        size: 7.5,
        bold: true,
      );
      cv.drawPath(
        WbArtPen.poly(_starPts(const Offset(258, 38), 8)),
        pen.fill(WbArtColors.yellow, 0.9),
      );
      pen.text(
        cv,
        'Kutup Yıldızı: hep KUZEYDE',
        const Offset(258, 54),
        size: 6.5,
        bold: true,
      );
      cv.drawLine(const Offset(190, 150), const Offset(326, 150), pen.line);
      final arc = Path()
        ..moveTo(196, 150)
        ..quadraticBezierTo(258, 60, 320, 150);
      pen.dashedPath(cv, arc, paint: pen.stroke(WbArtColors.orange, 0.6));
      for (final o in const [
        Offset(205, 128),
        Offset(258, 95),
        Offset(311, 128),
      ]) {
        cv.drawCircle(o, 6, pen.fill(WbArtColors.yellow, 0.9));
        cv.drawCircle(o, 6, pen.stroke(WbArtColors.orange, 0.5));
      }
      pen.text(
        cv,
        'Güneş doğar\nDOĞU',
        const Offset(205, 166),
        size: 6.5,
        bold: true,
      );
      pen.text(
        cv,
        'Güneş batar\nBATI',
        const Offset(311, 166),
        size: 6.5,
        bold: true,
      );
      pen.text(
        cv,
        'Öğlen: GÜNEY',
        const Offset(258, 108),
        size: 6.5,
        bold: true,
      );
      pen.text(cv, '(Kuzey Yarım Küre)', const Offset(258, 192), size: 6);
    },
    tags: 'yön bulma kuzey işareti güneş kutup yıldızı doğu batı yön pusula',
  ),
  WbArtItem(
    'sos_olcek',
    'Harita Ölçeği (Çizgi Ölçek)',
    340,
    206,
    (cv, pen) {
      pen.text(
        cv,
        'Kesirli ölçek:  1 / 100.000',
        const Offset(170, 12),
        size: 10,
        bold: true,
      );
      pen.text(
        cv,
        'Haritada 1 cm = Gerçekte 100.000 cm = 1 km',
        const Offset(170, 27),
        size: 7.5,
      );
      pen.text(
        cv,
        'Çizgi ölçek',
        const Offset(10, 52),
        size: 7.5,
        bold: true,
        anchor: 'left',
      );
      const x0 = 40.0;
      const seg = 60.0;
      for (int i = 0; i < 4; i++) {
        final r = Rect.fromLTWH(x0 + i * seg, 62, seg, 8);
        cv.drawRect(r, i.isEven ? pen.solid : pen.fill(pen.color, 0.0));
        cv.drawRect(r, pen.thin(0.8));
        pen.text(cv, '$i', Offset(x0 + i * seg, 80), size: 7.5);
      }
      pen.text(cv, '4 km', const Offset(x0 + 4 * seg, 80), size: 7.5);
      pen.text(cv, 'Her bölüm 1 cm = 1 km', const Offset(170, 96), size: 7);
      // Büyük ve küçük ölçek
      final blue = WbArtColors.blue;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(15, 108, 145, 76),
          const Radius.circular(4),
        ),
        pen.thin(0.6),
      );
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(180, 108, 145, 76),
          const Radius.circular(4),
        ),
        pen.thin(0.6),
      );
      // büyük ölçek: ev, yol, ağaç
      cv.drawRect(
        const Rect.fromLTWH(30, 140, 26, 20),
        pen.fill(WbArtColors.orange, 0.4),
      );
      cv.drawPath(
        WbArtPen.poly(const [
          Offset(28, 140),
          Offset(43, 128),
          Offset(58, 140),
        ]),
        pen.fill(WbArtColors.red, 0.5),
      );
      cv.drawRect(
        const Rect.fromLTWH(70, 144, 24, 16),
        pen.fill(WbArtColors.orange, 0.4),
      );
      cv.drawPath(
        WbArtPen.poly(const [
          Offset(68, 144),
          Offset(82, 134),
          Offset(96, 144),
        ]),
        pen.fill(WbArtColors.red, 0.5),
      );
      cv.drawLine(
        const Offset(18, 168),
        const Offset(158, 168),
        pen.stroke(WbArtColors.gray, 2),
      );
      cv.drawCircle(
        const Offset(122, 140),
        8,
        pen.fill(WbArtColors.green, 0.5),
      );
      cv.drawLine(const Offset(122, 148), const Offset(122, 160), pen.line);
      cv.drawPath(
        Path()
          ..moveTo(105, 112)
          ..quadraticBezierTo(110, 125, 135, 120)
          ..quadraticBezierTo(150, 117, 158, 125),
        pen.stroke(blue, 0.8),
      );
      pen.text(
        cv,
        'BÜYÜK ÖLÇEK (1/1.000)',
        const Offset(87, 193),
        size: 6.5,
        bold: true,
      );
      pen.text(cv, 'az alan, çok ayrıntı', const Offset(87, 202), size: 6.5);
      // küçük ölçek: kaba kara parçası ve şehir noktaları
      final land = Path()
        ..moveTo(200, 150)
        ..lineTo(215, 125)
        ..lineTo(245, 120)
        ..lineTo(270, 128)
        ..lineTo(300, 125)
        ..lineTo(312, 145)
        ..lineTo(290, 168)
        ..lineTo(250, 172)
        ..lineTo(220, 168)
        ..close();
      cv.drawPath(land, pen.fill(WbArtColors.green, 0.25));
      cv.drawPath(land, pen.thin(0.8));
      for (final o in const [
        Offset(235, 140),
        Offset(268, 150),
        Offset(290, 138),
      ]) {
        _dot(cv, pen, o, r: 1.8);
      }
      pen.text(
        cv,
        'KÜÇÜK ÖLÇEK (1/10.000.000)',
        const Offset(252, 193),
        size: 6.5,
        bold: true,
      );
      pen.text(cv, 'çok alan, az ayrıntı', const Offset(252, 202), size: 6.5);
    },
    tags:
        'harita ölçeği çizgi ölçek kesirli ölçek büyük ölçek küçük ölçek km cm',
  ),
  WbArtItem(
    'sos_izohips',
    'Eş Yükselti (İzohips) – Tepe ve Vadi',
    330,
    195,
    (cv, pen) {
      final brown = WbArtColors.brown;
      final blue = WbArtColors.blue;
      pen.text(cv, 'TEPE', const Offset(90, 10), size: 8.5, bold: true);
      pen.text(cv, 'VADİ', const Offset(250, 10), size: 8.5, bold: true);
      // Tepe: iç içe kapalı eğriler
      const cx = 90.0;
      const cy = 92.0;
      const levels = [100, 200, 300, 400];
      for (int k = 0; k < 4; k++) {
        final rx = 66.0 - k * 15;
        final ry = 56.0 - k * 13;
        final p = Path();
        for (int i = 0; i <= 60; i++) {
          final t = i * 2 * math.pi / 60;
          final wob = 1 + 0.07 * math.sin(3 * t + k) + 0.04 * math.cos(2 * t);
          final x = cx + rx * wob * math.cos(t);
          final y = cy + ry * wob * math.sin(t);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
        cv.drawPath(p, pen.fill(brown, 0.06 + k * 0.05));
        cv.drawPath(p, pen.stroke(brown, 0.8));
        pen.text(
          cv,
          '${levels[k]}',
          Offset(cx + rx * 0.72, cy - ry * 0.78),
          size: 6.5,
          c: brown,
          bold: true,
        );
      }
      cv.drawPath(
        WbArtPen.poly(_starPts(const Offset(cx, cy), 3.5)),
        pen.fill(WbArtColors.red),
      );
      pen.text(cv, 'zirve', const Offset(cx, cy + 9), size: 6.5);
      // Vadi: V biçimli eğriler, dere yukarıya doğru dar
      for (int k = 0; k < 4; k++) {
        final yb = 150.0 - k * 34;
        final p = Path();
        for (int i = 0; i <= 26; i++) {
          final x = 190.0 + i * 5;
          final u = (x - 255) / 60;
          final y = yb - 30 * math.exp(-u * u * 5);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        cv.drawPath(p, pen.stroke(brown, 0.8));
        pen.text(
          cv,
          '${levels[k]}',
          Offset(194, yb - 7),
          size: 6.5,
          c: brown,
          bold: true,
          anchor: 'left',
        );
      }
      final river = Path()
        ..moveTo(255, 18)
        ..lineTo(255, 168);
      cv.drawPath(river, pen.stroke(blue, 0.9));
      pen.arrow(
        cv,
        const Offset(255, 150),
        const Offset(255, 172),
        c: blue,
        size: 5,
        line: false,
      );
      pen.text(
        cv,
        'dere',
        const Offset(262, 30),
        size: 6.5,
        c: blue,
        anchor: 'left',
      );
      pen.text(
        cv,
        'Eğriler kapalı ve iç içe',
        const Offset(90, 170),
        size: 6.5,
      );
      pen.text(
        cv,
        'Eğriler yüksek yere doğru V',
        const Offset(255, 182),
        size: 6.5,
      );
      pen.text(
        cv,
        'Sık eğri = dik yamaç, seyrek = eğimsiz',
        const Offset(165, 190),
        size: 6.5,
        bold: true,
      );
    },
    tags:
        'eş yükselti izohips eğrileri tepe vadi yükselti harita topoğrafya kontur',
  ),
  WbArtItem(
    'sos_harita_sembol',
    'Harita Sembolleri Tablosu (Anahtar)',
    340,
    224,
    (cv, pen) {
      pen.text(
        cv,
        'HARİTA SEMBOLLERİ (ANAHTAR)',
        const Offset(170, 11),
        size: 9,
        bold: true,
      );
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 22, 336, 200),
          const Radius.circular(5),
        ),
        pen.thin(0.6),
      );
      cv.drawLine(const Offset(170, 22), const Offset(170, 222), pen.thin(0.3));
      final blue = WbArtColors.blue;
      final green = WbArtColors.darkGreen;
      final red = WbArtColors.red;
      const names = [
        'Şehir', 'Başkent', 'Karayolu', 'Demiryolu', 'Nehir', 'Göl', //
        'Ülke sınırı', 'Dağ / zirve', 'Havalimanı', 'Orman', 'Maden', 'Baraj',
      ];
      for (int i = 0; i < 12; i++) {
        final col = i ~/ 6;
        final row = i % 6;
        final x = 14.0 + col * 168;
        final y = 44.0 + row * 31;
        final c = Offset(x + 20, y);
        switch (i) {
          case 0:
            cv.drawCircle(c, 4, pen.fill(pen.color));
            cv.drawCircle(c, 4, pen.thin(0.6));
            break;
          case 1:
            cv.drawPath(WbArtPen.poly(_starPts(c, 7)), pen.fill(red));
            break;
          case 2:
            cv.drawLine(
              c + const Offset(-18, 0),
              c + const Offset(18, 0),
              pen.stroke(red, 1.6),
            );
            break;
          case 3:
            cv.drawLine(
              c + const Offset(-18, 0),
              c + const Offset(18, 0),
              pen.line,
            );
            for (int t = -15; t <= 15; t += 6) {
              cv.drawLine(
                c + Offset(t.toDouble(), -3),
                c + Offset(t.toDouble(), 3),
                pen.thin(0.8),
              );
            }
            break;
          case 4:
            final p = Path()..moveTo(c.dx - 18, c.dy);
            for (int t = 0; t < 4; t++) {
              p.quadraticBezierTo(
                c.dx - 13 + t * 9,
                c.dy - 6,
                c.dx - 9 + t * 9,
                c.dy,
              );
              p.quadraticBezierTo(
                c.dx - 4.5 + t * 9,
                c.dy + 6,
                c.dx - 0 + t * 9 - 0,
                c.dy,
              );
            }
            cv.drawPath(p, pen.stroke(blue, 0.9));
            break;
          case 5:
            cv.drawOval(
              Rect.fromCenter(center: c, width: 34, height: 18),
              pen.fill(blue, 0.35),
            );
            cv.drawOval(
              Rect.fromCenter(center: c, width: 34, height: 18),
              pen.stroke(blue, 0.6),
            );
            break;
          case 6:
            pen.dashed(
              cv,
              c + const Offset(-18, 0),
              c + const Offset(18, 0),
              dash: 7,
              gap: 3,
              paint: pen.stroke(pen.color, 1.0),
            );
            cv.drawCircle(c + const Offset(-9, 0), 0.9, pen.solid);
            cv.drawCircle(c + const Offset(9, 0), 0.9, pen.solid);
            break;
          case 7:
            _mtn(cv, pen, c, s: 8, col: WbArtColors.brown);
            pen.text(
              cv,
              '2000',
              c + const Offset(14, 3),
              size: 6,
              anchor: 'left',
            );
            break;
          case 8:
            cv.drawLine(
              c + const Offset(0, -10),
              c + const Offset(0, 10),
              pen.stroke(pen.color, 1.1),
            );
            cv.drawLine(
              c + const Offset(-10, -2),
              c + const Offset(10, -2),
              pen.stroke(pen.color, 1.1),
            );
            cv.drawLine(
              c + const Offset(-4, 9),
              c + const Offset(4, 9),
              pen.stroke(pen.color, 0.9),
            );
            break;
          case 9:
            for (final dx in const [-9.0, 0.0, 9.0]) {
              cv.drawPath(
                WbArtPen.poly([
                  c + Offset(dx, -9),
                  c + Offset(dx - 5, 3),
                  c + Offset(dx + 5, 3),
                ]),
                pen.fill(green, 0.7),
              );
              cv.drawLine(
                c + Offset(dx, 3),
                c + Offset(dx, 8),
                pen.stroke(WbArtColors.brown, 0.8),
              );
            }
            break;
          case 10:
            cv.drawLine(
              c + const Offset(-8, -8),
              c + const Offset(8, 8),
              pen.stroke(pen.color, 1.3),
            );
            cv.drawLine(
              c + const Offset(8, -8),
              c + const Offset(-8, 8),
              pen.stroke(pen.color, 1.3),
            );
            break;
          default:
            cv.drawLine(
              c + const Offset(-14, -6),
              c + const Offset(-14, 8),
              pen.stroke(pen.color, 1.6),
            );
            cv.drawLine(
              c + const Offset(14, -6),
              c + const Offset(14, 8),
              pen.stroke(pen.color, 1.6),
            );
            cv.drawLine(
              c + const Offset(-14, -6),
              c + const Offset(14, -6),
              pen.stroke(pen.color, 1.6),
            );
            cv.drawRect(
              Rect.fromLTRB(c.dx - 14, c.dy - 2, c.dx + 14, c.dy + 8),
              pen.fill(blue, 0.35),
            );
        }
        pen.text(
          cv,
          names[i],
          Offset(x + 52, y),
          size: 8,
          bold: true,
          anchor: 'left',
        );
      }
    },
    tags:
        'harita sembolleri anahtar lejant şehir başkent yol demiryolu nehir göl sınır dağ havalimanı orman maden baraj',
  ),

  // --------------------------- BÖLGESEL HARİTALAR --------------------------
  WbArtItem(
    'sos_avrupa_bos',
    'Avrupa Haritası (Kaba)',
    310,
    275,
    (cv, pen) {
      final pr = _mk(-26, 72, 4.2, 7.0);
      _regionMap(cv, pen, 310, 275, pr);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 310, 275));
      _trOn(cv, pen, pr, WbArtColors.red, alpha: 0.35);
      cv.restore();
      final names = <List<Object>>[
        ['İspanya', -3.5, 40.0],
        ['Fransa', 2.5, 46.8],
        ['Almanya', 10.3, 51.2],
        ['İtalya', 12.8, 42.8],
        ['İngiltere', -1.5, 53.0],
        ['İrlanda', -8.0, 53.3],
        ['İzlanda', -18.5, 64.8],
        ['Norveç', 9.5, 61.5],
        ['İsveç', 16.0, 62.5],
        ['Finlandiya', 26.0, 64.0],
        ['Polonya', 19.5, 52.2],
        ['Ukrayna', 31.0, 49.3],
        ['Rusya', 41.0, 58.0],
        ['Romanya', 25.0, 45.8],
        ['Yunanistan', 22.0, 39.4],
        ['Türkiye', 33.5, 39.2],
        ['Belarus', 28.0, 53.5],
        ['Portekiz', -8.0, 39.8],
      ];
      for (final n in names) {
        pen.text(
          cv,
          n[0] as String,
          pr(n[1] as double, n[2] as double),
          size: 6.5,
          bold: true,
        );
      }
      const caps = <_Pt>[
        _Pt('Londra', -0.1, 51.5, 'right'),
        _Pt('Paris', 2.35, 48.85, 'right'),
        _Pt('Berlin', 13.4, 52.5, 'top'),
        _Pt('Roma', 12.5, 41.9, 'right'),
        _Pt('Madrid', -3.7, 40.4, 'bottom'),
        _Pt('Moskova', 37.6, 55.75, 'top'),
        _Pt('Ankara', 32.85, 39.9, 'bottom'),
      ];
      for (final c in caps) {
        final o = pr(c.lon, c.lat);
        cv.drawPath(WbArtPen.poly(_starPts(o, 2.8)), pen.fill(WbArtColors.red));
      }
      final b = WbArtColors.blue;
      _lbl(cv, pen, pr, 'Atlas\nOkyanusu', -17, 45, size: 7, col: b);
      _lbl(cv, pen, pr, 'Kuzey\nDenizi', 3.5, 56.5, size: 6, col: b);
      _lbl(cv, pen, pr, 'Akdeniz', 14, 35.5, size: 7, col: b);
      _lbl(cv, pen, pr, 'Karadeniz', 34.5, 43.3, size: 6.5, col: b);
      _lbl(cv, pen, pr, 'Baltık\nDenizi', 19, 57.5, size: 5.5, col: b);
      pen.text(
        cv,
        '★ başkentler',
        const Offset(6, 266),
        size: 6.5,
        anchor: 'left',
      );
    },
    tags: 'avrupa harita kaba kıta ülkeler başkentler avrupa haritası',
  ),
  WbArtItem(
    'sos_ortadogu',
    'Orta Doğu ve Kafkasya (Türkiye Komşuları)',
    300,
    270,
    (cv, pen) {
      final pr = _mk(24, 44, 7.1, 8.0);
      _regionMap(cv, pen, 300, 270, pr);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 300, 270));
      _trOn(cv, pen, pr, WbArtColors.red, alpha: 0.4);
      cv.restore();
      final items = <List<Object>>[
        ['TÜRKİYE', 35.3, 39.1, true],
        ['Suriye', 38.6, 35.0, false],
        ['Irak', 43.5, 33.0, false],
        ['İran', 54.0, 32.5, false],
        ['Suudi Arabistan', 44.0, 24.5, false],
        ['Mısır', 30.0, 26.5, false],
        ['Ürdün', 36.7, 30.9, false],
        ['Yemen', 47.0, 15.8, false],
        ['Umman', 56.5, 20.5, false],
        ['Gürcistan', 43.4, 42.3, false],
        ['Ermenistan', 45.0, 40.3, false],
        ['Azerbaycan', 49.0, 40.3, false],
        ['Türkmenistan', 58.5, 39.0, false],
        ['Afganistan', 63.5, 34.0, false],
        ['Sudan', 31.0, 17.0, false],
      ];
      for (final n in items) {
        final main = n[3] as bool;
        pen.text(
          cv,
          n[0] as String,
          pr(n[1] as double, n[2] as double),
          size: main ? 9 : 6.5,
          bold: true,
          c: main ? WbArtColors.red : null,
        );
      }
      final b = WbArtColors.blue;
      _lbl(cv, pen, pr, 'Karadeniz', 34.5, 43.0, size: 6.5, col: b);
      _lbl(cv, pen, pr, 'Akdeniz', 30.0, 34.2, size: 7, col: b);
      _lbl(cv, pen, pr, 'Hazar\nDenizi', 51.2, 40.5, size: 6.5, col: b);
      _lbl(cv, pen, pr, 'Kızıl\nDeniz', 36.3, 21.0, size: 6, col: b);
      _lbl(cv, pen, pr, 'Basra\nKörfezi', 51.7, 27.4, size: 5.5, col: b);
      _lbl(cv, pen, pr, 'Arap Denizi', 60.5, 16.5, size: 7, col: b);
      for (final p in const [
        _Pt('Bağdat', 44.4, 33.3, 'left'),
        _Pt('Şam', 36.3, 33.5, 'right'),
        _Pt('Tahran', 51.4, 35.7, 'top'),
        _Pt('Kahire', 31.2, 30.0, 'left'),
        _Pt('Riyad', 46.7, 24.7, 'top'),
        _Pt('Bakü', 49.9, 40.4, 'top'),
      ]) {
        final o = pr(p.lon, p.lat);
        _dot(cv, pen, o, r: 1.6);
        _plabel(cv, pen, o, p.n, p.a, size: 6);
      }
    },
    tags:
        'orta doğu ortadoğu kafkasya harita türkiye komşuları suriye irak iran suudi arabistan mısır',
  ),
  WbArtItem(
    'sos_balkanlar',
    'Balkanlar Haritası (Kaba)',
    240,
    230,
    (cv, pen) {
      final pr = _mk(13, 47.5, 12.8, 17.0);
      _regionMap(cv, pen, 240, 230, pr);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 240, 230));
      _trOn(cv, pen, pr, WbArtColors.red, alpha: 0.35);
      cv.restore();
      final items = <List<Object>>[
        ['Slovenya', 14.9, 46.3],
        ['Hırvatistan', 16.4, 45.5],
        ['Bosna-Hersek', 17.9, 44.2],
        ['Sırbistan', 20.9, 44.1],
        ['Karadağ', 19.3, 42.8],
        ['K. Makedonya', 21.7, 41.6],
        ['Arnavutluk', 19.8, 40.6],
        ['Yunanistan', 22.0, 39.2],
        ['Bulgaristan', 25.2, 42.7],
        ['Romanya', 25.3, 45.6],
        ['Macaristan', 18.5, 47.1],
        ['Türkiye', 29.5, 39.5],
        ['Kosova', 20.9, 42.8],
      ];
      for (final n in items) {
        pen.text(
          cv,
          n[0] as String,
          pr(n[1] as double, n[2] as double),
          size: 6,
          bold: true,
        );
      }
      for (final p in const [
        _Pt('Belgrad', 20.46, 44.8, 'bottom'),
        _Pt('Atina', 23.7, 38.0, 'left'),
        _Pt('Sofya', 23.3, 42.7, 'bottom'),
        _Pt('Bükreş', 26.1, 44.4, 'left'),
        _Pt('Zagrep', 16.0, 45.8, 'left'),
        _Pt('Saraybosna', 18.4, 43.85, 'left'),
        _Pt('Üsküp', 21.4, 42.0, 'top'),
        _Pt('Tiran', 19.8, 41.3, 'right'),
        _Pt('İstanbul', 28.98, 41.0, 'bottom'),
      ]) {
        final o = pr(p.lon, p.lat);
        _dot(cv, pen, o, r: 1.5, col: WbArtColors.red);
        _plabel(cv, pen, o, p.n, p.a, size: 5.5);
      }
      final b = WbArtColors.blue;
      _lbl(cv, pen, pr, 'Adriyatik\nDenizi', 15.2, 43.0, size: 6, col: b);
      _lbl(cv, pen, pr, 'Karadeniz', 30.0, 43.6, size: 6.5, col: b);
      _lbl(cv, pen, pr, 'Ege\nDenizi', 25.3, 38.4, size: 6.5, col: b);
      _lbl(cv, pen, pr, 'İyon\nDenizi', 18.5, 38.2, size: 6, col: b);
    },
    tags:
        'balkanlar harita kaba balkan yarımadası yunanistan bulgaristan sırbistan romanya',
  ),

  // ------------------------------- TARİH ------------------------------------
  WbArtItem(
    'sos_tarih_zaman',
    'Zaman Çizelgesi Şablonu',
    360,
    130,
    (cv, pen) {
      const bounds = [15.0, 80.0, 150.0, 215.0, 280.0, 340.0];
      const names = [
        'Tarih Öncesi',
        'İlk Çağ',
        'Orta Çağ',
        'Yeni Çağ',
        'Yakın Çağ',
      ];
      const cols = [
        WbArtColors.gray,
        WbArtColors.orange,
        WbArtColors.green,
        WbArtColors.blue,
        WbArtColors.purple,
      ];
      for (int i = 0; i < 5; i++) {
        final r = Rect.fromLTRB(bounds[i], 57, bounds[i + 1], 75);
        cv.drawRect(r, pen.fill(cols[i], 0.35));
        cv.drawRect(r, pen.stroke(cols[i], 0.6));
        pen.text(cv, names[i], r.center, size: 7.5, bold: true);
      }
      pen.arrow(cv, const Offset(338, 66), const Offset(354, 66), size: 8);
      const years = ['MÖ 3200', 'MS 476', '1453', '1789'];
      const events = [
        'Yazının icadı',
        'Batı Roma\'nın yıkılışı',
        'İstanbul\'un fethi',
        'Fransız İhtilali',
      ];
      for (int i = 0; i < 4; i++) {
        final x = bounds[i + 1];
        final up = i.isEven;
        cv.drawLine(
          Offset(x, up ? 57 : 75),
          Offset(x, up ? 38 : 94),
          pen.thin(0.7),
        );
        cv.drawCircle(Offset(x, up ? 38 : 94), 2, pen.solid);
        pen.text(cv, years[i], Offset(x, up ? 28 : 104), size: 7.5, bold: true);
        pen.text(cv, events[i], Offset(x, up ? 17 : 115), size: 6.5);
      }
      pen.text(
        cv,
        'MÖ 3200 ← yazının bulunuşu → Tarih Çağları başlar',
        const Offset(180, 124),
        size: 6,
      );
    },
    tags: 'tarih zaman çizelgesi şablon kronoloji çağlar ok olaylar yıllar',
  ),
  WbArtItem(
    'sos_tarih_soyagaci',
    'Soy Ağacı Şablonu',
    320,
    195,
    (cv, pen) {
      final blue = WbArtColors.blue;
      final pink = WbArtColors.pink;
      final green = WbArtColors.green;
      const gx = [45.0, 125.0, 205.0, 285.0];
      const gn = ['Büyükbaba', 'Büyükanne', 'Büyükbaba', 'Büyükanne'];
      for (int i = 0; i < 4; i++) {
        _box(
          cv,
          pen,
          Rect.fromCenter(center: Offset(gx[i], 22), width: 70, height: 24),
          gn[i],
          i.isEven ? blue : pink,
          size: 7.5,
        );
      }
      // evlilik bağları
      cv.drawLine(const Offset(80, 22), const Offset(90, 22), pen.line);
      cv.drawLine(const Offset(240, 22), const Offset(250, 22), pen.line);
      // ebeveynler
      _box(
        cv,
        pen,
        Rect.fromCenter(center: const Offset(85, 97), width: 70, height: 24),
        'Baba',
        blue,
        size: 8,
      );
      _box(
        cv,
        pen,
        Rect.fromCenter(center: const Offset(245, 97), width: 70, height: 24),
        'Anne',
        pink,
        size: 8,
      );
      cv.drawLine(const Offset(85, 22), const Offset(85, 85), pen.thin(0.8));
      cv.drawLine(const Offset(245, 22), const Offset(245, 85), pen.thin(0.8));
      cv.drawLine(const Offset(120, 97), const Offset(210, 97), pen.line);
      // çocuklar
      cv.drawLine(const Offset(165, 97), const Offset(165, 130), pen.thin(0.8));
      cv.drawLine(const Offset(85, 130), const Offset(245, 130), pen.thin(0.8));
      const cxs = [85.0, 165.0, 245.0];
      const cn = ['Kardeş', 'Ben', 'Kardeş'];
      for (int i = 0; i < 3; i++) {
        cv.drawLine(Offset(cxs[i], 130), Offset(cxs[i], 148), pen.thin(0.8));
        _box(
          cv,
          pen,
          Rect.fromCenter(center: Offset(cxs[i], 160), width: 70, height: 24),
          cn[i],
          green,
          size: 8,
        );
      }
      pen.text(cv, '1. kuşak', const Offset(165, 8), size: 6.5);
      pen.text(cv, '2. kuşak (ebeveynler)', const Offset(165, 76), size: 6.5);
      pen.text(cv, '3. kuşak (çocuklar)', const Offset(165, 184), size: 6.5);
    },
    tags: 'soy ağacı aile şablon dede nine anne baba kardeş akrabalık tarih',
  ),
  WbArtItem(
    'sos_tarih_osmanli',
    'Osmanlı Genişleme Taslağı',
    350,
    300,
    (cv, pen) {
      final pr = _mk(-8, 50, 6.0, 7.0);
      _frame(cv, pen, 350, 266);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 350, 266));
      _drawLands(cv, pen, pr, uni: pen.color, alpha: 0.08, line: 0.6);
      cv.save();
      cv.clipPath(_landUnion(pr));
      const polys = <List<double>>[
        [
          3,
          37.5,
          1,
          34,
          8,
          31,
          15,
          29,
          24,
          25,
          33,
          22,
          37.3,
          19,
          39,
          19,
          41,
          16,
          43,
          12.5, //
          44.5,
          14,
          45,
          19,
          48,
          22,
          49,
          26.5,
          49,
          29,
          48.5,
          30.2,
          46,
          32.5,
          46.5,
          36,
          47,
          38,
          49.5,
          40.5,
          48,
          42,
          46,
          41.5,
          45,
          43,
          40,
          45,
          35,
          45.8,
          33,
          46.2,
          31,
          47,
          28,
          48.5,
          25,
          48.5,
          22,
          48.3,
          20,
          48,
          17.5,
          47.8,
          16,
          46.2,
          16,
          45.3,
          18,
          43.5,
          19,
          41.8,
          18,
          40,
          17.5, 38, 10, 37.8,
        ],
        [
          19,
          38,
          19.5,
          41.5,
          19,
          43.3,
          17.2,
          44,
          18.5,
          45.2,
          20.5,
          45,
          23,
          44,
          26,
          43.8,
          28.5,
          44.2, //
          29.7,
          45.3,
          33,
          44.6,
          36.5,
          45.2,
          38,
          43,
          41.5,
          42,
          43,
          41,
          44.5,
          39.5,
          44.5,
          37.5,
          41,
          36.5,
          41,
          34,
          39,
          29,
          40,
          22,
          39,
          19,
          37.3,
          19,
          33,
          22,
          25,
          22,
          25,
          30.5,
          25,
          35,
        ],
        [
          19,
          38,
          19.5,
          41.5,
          19,
          43.3,
          17.2,
          44,
          18.5,
          45.2,
          20.5,
          45,
          23,
          44,
          26,
          43.8,
          28.5,
          44.2, //
          29.7,
          45.3,
          33,
          44.6,
          36.5,
          45.2,
          38,
          43,
          41.5,
          42,
          42,
          40.5,
          40,
          39.5,
          38.5,
          38,
          37.5, 37, 36.5, 36.2, 34, 36, 30, 35.5, 26, 35, 21, 35.5,
        ],
        [29, 40.3, 30, 39.4, 31.4, 39.7, 31.4, 40.6, 30, 40.8],
      ];
      const cols = [
        WbArtColors.orange,
        WbArtColors.red,
        WbArtColors.purple,
        WbArtColors.blue,
      ];
      for (int i = 0; i < polys.length; i++) {
        final p = _pp(polys[i], pr);
        cv.drawPath(p, pen.fill(cols[i], i == 3 ? 0.9 : 0.35));
      }
      cv.restore();
      cv.restore();
      _trOn(cv, pen, pr, WbArtColors.red, alpha: 0.0);
      pen.text(
        cv,
        'Söğüt',
        pr(30.2, 40.0),
        size: 6,
        bold: true,
        anchor: 'right',
      );
      _dot(cv, pen, pr(30.2, 40.0), r: 1.6, col: WbArtColors.red);
      for (final p in const [
        _Pt('İstanbul', 28.98, 41.0, 'bottom'),
        _Pt('Bursa', 29.06, 40.18, 'top'),
        _Pt('Kahire', 31.2, 30.0, 'left'),
        _Pt('Belgrad', 20.46, 44.8, 'bottom'),
        _Pt('Viyana\'ya kadar', 16.4, 48.2, 'left'),
        _Pt('Bağdat', 44.4, 33.3, 'left'),
      ]) {
        final o = pr(p.lon, p.lat);
        _dot(cv, pen, o, r: 1.5, col: WbArtColors.red);
        _plabel(cv, pen, o, p.n, p.a, size: 5.5);
      }
      // anahtar
      const names = [
        '1300 (Söğüt)',
        '1453-1481',
        '1520 (Yavuz)',
        '1683 (en geniş sınır)',
      ];
      const lc = [
        WbArtColors.blue,
        WbArtColors.purple,
        WbArtColors.red,
        WbArtColors.orange,
      ];
      const lx = [8.0, 82.0, 156.0, 232.0];
      for (int i = 0; i < 4; i++) {
        cv.drawRect(Rect.fromLTWH(lx[i], 276, 9, 7), pen.fill(lc[i], 0.7));
        pen.text(
          cv,
          names[i],
          Offset(lx[i] + 12, 279.5),
          size: 6.5,
          anchor: 'left',
        );
      }
      pen.text(
        cv,
        'Osmanlı Devleti\'nin genişleme dönemleri (kaba taslak)',
        const Offset(175, 293),
        size: 6.5,
        bold: true,
      );
    },
    tags:
        'osmanlı genişleme taslağı osmanlı devleti sınırları harita fetih dönemleri tarih söğüt viyana',
  ),
  WbArtItem(
    'sos_tarih_savas',
    'Savaş Ok Planı Örneği',
    320,
    206,
    (cv, pen) {
      final red = WbArtColors.red;
      final blue = WbArtColors.blue;
      final brown = WbArtColors.brown;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1, 1, 318, 182),
          const Radius.circular(5),
        ),
        pen.thin(0.6),
      );
      // Tepe
      cv.drawOval(const Rect.fromLTWH(190, 24, 100, 56), pen.fill(brown, 0.15));
      cv.drawOval(const Rect.fromLTWH(210, 34, 60, 34), pen.fill(brown, 0.15));
      cv.drawOval(
        const Rect.fromLTWH(190, 24, 100, 56),
        pen.stroke(brown, 0.5),
      );
      cv.drawOval(const Rect.fromLTWH(210, 34, 60, 34), pen.stroke(brown, 0.5));
      pen.text(cv, 'Tepe', const Offset(240, 82), size: 6.5, c: brown);
      // Nehir
      final river = Path()
        ..moveTo(2, 118)
        ..cubicTo(100, 98, 200, 140, 318, 104);
      cv.drawPath(river, pen.stroke(blue, 2.2));
      pen.text(cv, 'Nehir', const Offset(36, 106), size: 6.5, c: blue);
      // Düşman
      _box(
        cv,
        pen,
        const Rect.fromLTWH(30, 14, 56, 22),
        'Düşman\nPiyade',
        red,
        size: 6.5,
      );
      _box(
        cv,
        pen,
        const Rect.fromLTWH(100, 14, 56, 22),
        'Düşman\nSüvari',
        red,
        size: 6.5,
      );
      _box(
        cv,
        pen,
        const Rect.fromLTWH(212, 40, 56, 22),
        'Düşman\nOkçu',
        red,
        size: 6.5,
      );
      // Kendi ordu
      _box(
        cv,
        pen,
        const Rect.fromLTWH(30, 150, 62, 24),
        'Ana Kuvvet',
        blue,
        size: 7,
      );
      _box(
        cv,
        pen,
        const Rect.fromLTWH(112, 158, 56, 22),
        'Yedek',
        blue,
        size: 7,
      );
      _box(
        cv,
        pen,
        const Rect.fromLTWH(242, 150, 62, 24),
        'Süvari',
        blue,
        size: 7,
      );
      // Saldırı okları
      pen.arrow(
        cv,
        const Offset(61, 148),
        const Offset(58, 40),
        c: blue,
        size: 8,
      );
      final flank = Path()
        ..moveTo(273, 148)
        ..cubicTo(318, 125, 300, 85, 272, 62);
      cv.drawPath(flank, pen.stroke(blue, 1.0));
      pen.arrow(
        cv,
        const Offset(290, 82),
        const Offset(270, 64),
        c: blue,
        size: 7,
        line: false,
      );
      pen.text(
        cv,
        'Kanat\nsaldırısı',
        const Offset(300, 100),
        size: 6.5,
        c: blue,
        bold: true,
      );
      pen.text(
        cv,
        'Ana\nsaldırı',
        const Offset(36, 96),
        size: 6.5,
        c: blue,
        bold: true,
      );
      // Geri çekilme
      pen.dashed(
        cv,
        const Offset(128, 36),
        const Offset(150, 60),
        dash: 4,
        gap: 3,
        paint: pen.stroke(red, 0.9),
      );
      pen.arrow(
        cv,
        const Offset(140, 52),
        const Offset(152, 62),
        c: red,
        size: 6,
        line: false,
      );
      pen.text(
        cv,
        'Geri çekilme',
        const Offset(168, 62),
        size: 6.5,
        c: red,
        bold: true,
      );
      // Anahtar
      cv.drawRect(const Rect.fromLTWH(6, 192, 9, 7), pen.fill(blue, 0.6));
      pen.text(
        cv,
        'Kendi ordu',
        const Offset(18, 195.5),
        size: 6.5,
        anchor: 'left',
      );
      cv.drawRect(const Rect.fromLTWH(78, 192, 9, 7), pen.fill(red, 0.6));
      pen.text(
        cv,
        'Düşman',
        const Offset(90, 195.5),
        size: 6.5,
        anchor: 'left',
      );
      pen.arrow(
        cv,
        const Offset(134, 195.5),
        const Offset(152, 195.5),
        c: blue,
        size: 5,
      );
      pen.text(
        cv,
        'Saldırı',
        const Offset(156, 195.5),
        size: 6.5,
        anchor: 'left',
      );
      pen.dashed(
        cv,
        const Offset(196, 195.5),
        const Offset(214, 195.5),
        dash: 3,
        gap: 2,
        paint: pen.stroke(red, 0.9),
      );
      pen.text(
        cv,
        'Geri çekilme',
        const Offset(218, 195.5),
        size: 6.5,
        anchor: 'left',
      );
    },
    tags:
        'savaş ok planı muharebe plan saldırı kanat geri çekilme ordu tarih harekât',
  ),
  WbArtItem(
    'sos_tarih_nehir_uyg',
    'İlk Çağ Nehir Uygarlıkları',
    330,
    165,
    (cv, pen) {
      final pr = _mk(22, 48, 3.1, 3.6);
      _frame(cv, pen, 330, 151);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 330, 151));
      _drawLands(cv, pen, pr, uni: WbArtColors.gray, alpha: 0.2, line: 0.5);
      final blue = WbArtColors.blue;
      const zones = <List<double>>[
        [31.2, 27.5, 2.2, 5.5], // Nil
        [44.5, 33.0, 4.5, 2.2], // Mezopotamya
        [71.0, 28.0, 4.0, 4.0], // Hint
        [113.0, 36.5, 5.0, 2.8], // Çin
      ];
      for (final z in zones) {
        final r = Rect.fromCenter(
          center: pr(z[0], z[1]),
          width: z[2] * 2 * 3.1,
          height: z[3] * 2 * 3.6,
        );
        cv.drawOval(r, pen.fill(WbArtColors.yellow, 0.35));
        cv.drawOval(r, pen.stroke(WbArtColors.orange, 0.4));
      }
      final rp = pen.stroke(blue, 1.1);
      const rivers = <List<double>>[
        [
          31.2,
          31.4,
          31.2,
          30.0,
          32.6,
          25.7,
          32.9,
          24.0,
          31.6,
          21.0,
          30.5,
          19.5,
          32.0,
          16.0,
          32.5,
          15.6,
          31.6,
          9.5,
        ],
        [
          41.0,
          38.0,
          41.0,
          37.0,
          43.0,
          36.0,
          43.9,
          34.3,
          44.4,
          33.3,
          46.0,
          31.5,
          48.3,
          30.0,
        ],
        [
          39.0,
          40.0,
          39.5,
          38.5,
          38.0,
          37.0,
          39.0,
          35.5,
          41.0,
          34.4,
          43.3,
          33.4,
          44.4,
          32.3,
          46.0,
          31.0,
        ],
        [
          79.0,
          30.5,
          80.0,
          27.0,
          83.0,
          25.5,
          85.5,
          25.5,
          88.0,
          24.5,
          90.0,
          23.0,
        ],
        [77.0, 35.0, 74.0, 33.0, 72.0, 29.0, 68.0, 25.0, 67.5, 24.0],
        [
          96.0,
          35.0,
          100.0,
          35.5,
          102.0,
          33.0,
          102.0,
          36.0,
          104.0,
          36.5,
          106.0,
          38.0,
          110.0,
          40.5,
          111.0,
          38.0,
          110.5,
          35.5,
          114.0,
          34.8,
          118.0,
          37.0,
          119.0,
          37.7,
        ],
      ];
      for (final r in rivers) {
        cv.drawPath(_pl(r, pr), rp);
      }
      cv.restore();
      final red = WbArtColors.red;
      pen.text(
        cv,
        'Nil\nMısır',
        pr(31.0, 33.0) + const Offset(-4, 0),
        size: 6.5,
        c: red,
        bold: true,
        anchor: 'right',
      );
      pen.text(
        cv,
        'Dicle-Fırat\nMezopotamya',
        pr(44.5, 38.0),
        size: 6.5,
        c: red,
        bold: true,
      );
      pen.text(
        cv,
        'İndus-Ganj\nHint',
        pr(75.0, 21.0),
        size: 6.5,
        c: red,
        bold: true,
      );
      pen.text(
        cv,
        'Sarı Irmak\n(Huang He)\nÇin',
        pr(115.0, 42.0),
        size: 6.5,
        c: red,
        bold: true,
      );
      final b = WbArtColors.blue;
      _lbl(cv, pen, pr, 'Akdeniz', 18 + 6, 34.5, size: 6, col: b);
      _lbl(cv, pen, pr, 'Hint Okyanusu', 80, 10, size: 6.5, col: b);
      pen.text(
        cv,
        'Uygarlıklar büyük nehir vadilerinde doğdu',
        const Offset(165, 158),
        size: 6.5,
        bold: true,
      );
    },
    tags:
        'ilk çağ nehir uygarlıkları nil dicle fırat ganj indus sarı ırmak mısır mezopotamya hint çin tarih harita',
  ),
  WbArtItem(
    'sos_tarih_seridi',
    'Tarih Öncesi Çağlar Şeridi',
    390,
    110,
    (cv, pen) {
      const names = [
        'Paleolitik\n(Eski Taş)',
        'Mezolitik\n(Orta Taş)',
        'Neolitik\n(Cilalı Taş)',
        'Kalkolitik\n(Bakır)',
        'Tunç\nÇağı',
        'Demir\nÇağı',
      ];
      const subs = [
        'Avcı-toplayıcı\nateşin bulunuşu',
        'Göçebe\nküçük aletler',
        'Tarım, yerleşik\nhayvan evcilleştirme',
        'Bakırın\nkullanımı',
        'Tunç alaşımı\nyazının icadı',
        'Demir araçlar\nsilahlar',
      ];
      const cols = [
        WbArtColors.brown,
        WbArtColors.orange,
        WbArtColors.green,
        WbArtColors.teal,
        WbArtColors.blue,
        WbArtColors.purple,
      ];
      const w = 60.0;
      for (int i = 0; i < 6; i++) {
        final x = 4.0 + i * w;
        final p = Path()
          ..moveTo(x, 20)
          ..lineTo(x + w - 8, 20)
          ..lineTo(x + w, 40)
          ..lineTo(x + w - 8, 60)
          ..lineTo(x, 60)
          ..lineTo(x + 8, 40)
          ..close();
        cv.drawPath(p, pen.fill(cols[i], 0.35));
        cv.drawPath(p, pen.stroke(cols[i], 0.6));
        pen.text(cv, names[i], Offset(x + w / 2, 40), size: 6.5, bold: true);
        pen.text(cv, subs[i], Offset(x + w / 2, 80), size: 5.5);
        cv.drawLine(
          Offset(x + w / 2, 60),
          Offset(x + w / 2, 70),
          pen.thin(0.5),
        );
      }
      pen.arrow(cv, const Offset(364, 40), const Offset(386, 40), size: 7);
      pen.text(cv, 'Tarih Çağları', const Offset(374, 27), size: 6, bold: true);
      pen.text(
        cv,
        'Tarih Öncesi Çağlar  (yazıdan önce)',
        const Offset(150, 8),
        size: 7.5,
        bold: true,
      );
      pen.text(cv, 'Taş Devri', const Offset(94, 100), size: 6.5, bold: true);
      cv.drawLine(const Offset(10, 94), const Offset(184, 94), pen.thin(0.6));
      pen.text(
        cv,
        'Maden Devri',
        const Offset(272, 100),
        size: 6.5,
        bold: true,
      );
      cv.drawLine(const Offset(190, 94), const Offset(364, 94), pen.thin(0.6));
    },
    tags:
        'tarih öncesi çağlar şeridi paleolitik mezolitik neolitik kalkolitik tunç demir taş devri maden zaman',
  ),
  WbArtItem(
    'sos_tarih_ipek',
    'İpek Yolu Taslağı',
    330,
    130,
    (cv, pen) {
      final pr = _mk(5, 56, 2.64, 3.3);
      _frame(cv, pen, 330, 120);
      cv.save();
      cv.clipRect(const Rect.fromLTWH(0, 0, 330, 120));
      _drawLands(cv, pen, pr, uni: WbArtColors.gray, alpha: 0.2, line: 0.5);
      final red = WbArtColors.red;
      const route = <double>[
        108.9,
        34.3,
        103.8,
        36.0,
        98.0,
        39.8,
        94.7,
        40.1,
        89.2,
        42.9,
        83.5,
        41.8,
        75.9,
        39.5, //
        66.9,
        39.7,
        62.2,
        37.7,
        51.4,
        35.7,
        48.5,
        34.8,
        44.4,
        33.3,
        38.3,
        34.5,
        36.2,
        36.2,
        32.5, 39.0, 29.0, 41.0, 23.5, 41.0, 20.0, 42.0, 15.0, 44.5, 12.3, 45.4,
      ];
      cv.drawPath(_pl(route, pr), pen.stroke(red, 1.2));
      // Güney kolu (Hindistan'a)
      const south = <double>[
        75.9,
        39.5,
        72.8,
        33.7,
        68.0,
        30.0,
        62.0,
        27.0,
        58.0,
        25.5,
      ];
      pen.dashedPath(
        cv,
        _pl(south, pr),
        paint: pen.stroke(WbArtColors.orange, 0.8),
      );
      cv.restore();
      for (final p in const [
        _Pt('Çan-an (Xi\'an)', 108.9, 34.3, 'bottom'),
        _Pt('Kaşgar', 75.9, 39.5, 'bottom'),
        _Pt('Semerkant', 66.9, 39.7, 'bottom'),
        _Pt('Tahran', 51.4, 35.7, 'top'),
        _Pt('Bağdat', 44.4, 33.3, 'top'),
        _Pt('Antakya', 36.2, 36.2, 'top'),
        _Pt('İstanbul', 29.0, 41.0, 'bottom'),
        _Pt('Venedik', 12.3, 45.4, 'right'),
      ]) {
        final o = pr(p.lon, p.lat);
        _dot(cv, pen, o, r: 2, col: red);
        _plabel(cv, pen, o, p.n, p.a, size: 6.5, bold: true);
      }
      pen.text(
        cv,
        'İPEK YOLU',
        const Offset(165, 12),
        size: 10,
        c: red,
        bold: true,
      );
      pen.text(
        cv,
        'Hindistan kolu',
        pr(64, 28.0) + const Offset(0, 8),
        size: 6,
        c: WbArtColors.orange,
      );
      pen.text(
        cv,
        'Çin\'den Avrupa\'ya ipek, baharat ve fikir ticareti',
        const Offset(165, 125),
        size: 6.5,
        bold: true,
      );
    },
    tags:
        'ipek yolu taslağı ticaret yolu çin avrupa semerkant bağdat istanbul venedik tarih harita',
  ),
];
