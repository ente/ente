import "package:flutter/material.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class ClosingPage extends RewindPage {
  const ClosingPage();

  @override
  String get key => "closing";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return ColoredBox(
      color: const Color(0xFF3A1B1B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "That was your ${RewindEdition.year}",
              textAlign: TextAlign.center,
              style: getEnteTextTheme(
                context,
              ).h2Bold.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Done", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
