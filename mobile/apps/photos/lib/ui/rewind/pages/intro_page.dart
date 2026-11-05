import "package:flutter/material.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class IntroPage extends RewindPage {
  const IntroPage();

  @override
  String get key => "intro";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return ColoredBox(
      color: const Color(0xFF1B1B3A),
      child: Center(
        child: Text(
          "Your ${RewindEdition.year}\nRewind",
          textAlign: TextAlign.center,
          style: getEnteTextTheme(context).h1Bold.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
