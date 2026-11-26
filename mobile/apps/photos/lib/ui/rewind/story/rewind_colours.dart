import "dart:ui";

import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/theme/rewind_colors.dart";

extension RewindColourLook on rust.RewindColour {
  Color get color => switch (this) {
    rust.RewindColour.cherryBomb => const Color(0xFF920000),
    rust.RewindColour.tangerinePop => const Color(0xFFD9560B),
    rust.RewindColour.lemonDrop => const Color(0xFFF5BE1E),
    rust.RewindColour.pistachio => const Color(0xFF2E8B3E),
    rust.RewindColour.berryBlue => const Color(0xFF1F4FD1),
    rust.RewindColour.lavenderFizz => const Color(0xFF7A4FD6),
    rust.RewindColour.bubblegum => const Color(0xFFE0287A),
    rust.RewindColour.hotCocoa => const Color(0xFF6B3A1F),
    rust.RewindColour.marshmallow => const Color(0xFFE6DFD3),
    rust.RewindColour.midnightCola => const Color(0xFF1A1A1A),
  };

  Color get stripe => switch (this) {
    rust.RewindColour.cherryBomb => const Color(0xFF960A0A),
    rust.RewindColour.tangerinePop => const Color(0xFFDB5D15),
    rust.RewindColour.lemonDrop => const Color(0xFFF5C127),
    rust.RewindColour.pistachio => const Color(0xFF369046),
    rust.RewindColour.berryBlue => const Color(0xFF2856D3),
    rust.RewindColour.lavenderFizz => const Color(0xFF7F56D8),
    rust.RewindColour.bubblegum => const Color(0xFFE1317F),
    rust.RewindColour.hotCocoa => const Color(0xFF714228),
    rust.RewindColour.marshmallow => const Color(0xFFEEE9E0),
    rust.RewindColour.midnightCola => const Color(0xFF232323),
  };

  Color get text => switch (this) {
    rust.RewindColour.lemonDrop ||
    rust.RewindColour.marshmallow => RewindColors.ink,
    _ => RewindColors.cream,
  };

  String get hex {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return "#${rgb.toRadixString(16).padLeft(6, "0").toUpperCase()}";
  }
}
