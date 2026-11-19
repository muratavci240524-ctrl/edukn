import 'package:flutter/material.dart';

import 'whiteboard_art_chem.dart';
import 'whiteboard_art_core.dart';
import 'whiteboard_art_general.dart';
import 'whiteboard_art_math.dart';
import 'whiteboard_art_physics.dart';
import 'whiteboard_art_science.dart';
import 'whiteboard_art_social.dart';

export 'whiteboard_art_core.dart';

/// Şekil kütüphanesinin tüm ders grupları.
final List<WbArtCategory> wbArtCatalog = [
  WbArtCategory('mat', 'Matematik', Icons.functions_rounded, const Color(0xFF2563EB), wbArtMath),
  WbArtCategory('fiz', 'Fizik', Icons.bolt_rounded, const Color(0xFFEA580C), wbArtPhysics),
  WbArtCategory('kim', 'Kimya', Icons.science_rounded, const Color(0xFF7C3AED), wbArtChemistry),
  WbArtCategory('fen', 'Fen / Biyoloji', Icons.eco_rounded, const Color(0xFF16A34A), wbArtScience),
  WbArtCategory('sos', 'Harita / Sosyal', Icons.public_rounded, const Color(0xFF0D9488), wbArtSocial),
  WbArtCategory('gen', 'Genel', Icons.account_tree_rounded, const Color(0xFF475569), wbArtGeneral),
];

final Map<String, WbArtItem> _byId = {
  for (final c in wbArtCatalog)
    for (final i in c.items) i.id: i,
};

/// Kimliğe göre şekil bulur (yoksa null).
WbArtItem? wbArtById(String id) => _byId[id];

