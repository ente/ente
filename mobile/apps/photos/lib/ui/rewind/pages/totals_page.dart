import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class TotalsPage extends RewindPage {
  const TotalsPage(this.totals);

  final rust.Totals totals;

  @override
  String get key => "totals";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final textTheme = getEnteTextTheme(context);
    return ColoredBox(
      color: const Color(0xFF0F3D2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "In ${RewindEdition.year} you kept",
              style: textTheme.large.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              NumberFormat.decimalPattern().format(totals.files),
              style: textTheme.h1Bold.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              totals.files == 1 ? "photo or video" : "photos and videos",
              style: textTheme.large.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
