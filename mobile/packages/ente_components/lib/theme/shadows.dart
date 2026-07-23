import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=57-6281&m=dev
/// Section: Design system / Shadows
/// Specs: Subtle elevation shadows for sheets, overlays, and floating controls.
class Shadows {
  const Shadows._();

  static const soft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
  ];

  static const floating = [
    BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 12)),
  ];
}
