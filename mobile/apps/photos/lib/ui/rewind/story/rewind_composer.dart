import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/pages/closing_page.dart";
import "package:photos/ui/rewind/pages/intro_page.dart";
import "package:photos/ui/rewind/pages/totals_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

List<RewindPage> composeRewind(rust.RewindReport report) {
  final totals = report.totals;
  return [
    const IntroPage(),
    if (totals != null) TotalsPage(totals),
    const ClosingPage(),
  ];
}
