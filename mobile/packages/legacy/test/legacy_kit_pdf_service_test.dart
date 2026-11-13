import "dart:async";
import "dart:convert";
import "dart:io";

import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/services/legacy_kit_pdf_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

final _strings = lookupStringsLocalizations(const Locale("en"));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("formats recovery URL for recovery sheet instructions", () {
    expect(
      LegacyKitPdfService.displayRecoveryUrl("https://legacy.ente.com/"),
      "legacy.ente.com",
    );
    expect(
      LegacyKitPdfService.displayRecoveryUrl(" http://localhost:3013/ "),
      "localhost:3013",
    );
    expect(
      LegacyKitPdfService.displayRecoveryUrl("https://legacy.example.com/r"),
      "legacy.example.com/r",
    );
  });

  test("builds individual legacy kit recovery sheet PDFs", () async {
    final shares = [_share(1), _share(2), _share(3)];

    const service = LegacyKitPdfService();
    final sheets = await Future.wait(
      shares.map(
        (share) => service.buildRecoverySheet(
          accountEmail: "john@example.com",
          recoveryUrl: "http://localhost:3013",
          share: share,
          allShares: shares,
          strings: _strings,
        ),
      ),
    );

    for (var index = 0; index < sheets.length; index++) {
      expect(String.fromCharCodes(sheets[index].take(4)), "%PDF");
      expect(String.fromCharCodes(sheets[index]), isNot(contains("/Keywords")));
    }
  });

  test(
    "embeds the sheet fonts instead of falling back to a base font",
    () async {
      final shares = [_share(1), _share(2)];
      const service = LegacyKitPdfService();
      final sheet = await service.buildRecoverySheet(
        accountEmail: "john@example.com",
        recoveryUrl: "https://legacy.ente.com",
        share: shares.first,
        allShares: shares,
        strings: _strings,
      );

      final fonts = _embeddedFonts(sheet);
      expect(
        fonts,
        containsAll([
          "Outfit-SemiBold",
          "Outfit-Medium",
          "Inter-Medium",
          "Inter-Bold",
        ]),
      );
      expect(
        fonts.where(
          (font) =>
              font.startsWith("Courier") ||
              font.startsWith("Helvetica") ||
              font.startsWith("Times"),
        ),
        isEmpty,
      );
    },
  );

  test("renders Cyrillic holder names without missing glyphs", () async {
    final printedMessages = <String>[];
    final shares = [_share(1), _share(2)];

    final sheet = await runZoned(
      () => const LegacyKitPdfService().buildRecoverySheet(
        accountEmail: "john@example.com",
        recoveryUrl: "https://legacy.ente.com",
        share: shares.first,
        allShares: shares,
        strings: _strings,
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, message) => printedMessages.add(message),
      ),
    );

    expect(String.fromCharCodes(sheet.take(4)), "%PDF");
    expect(
      printedMessages.where(
        (message) => message.contains("Unable to find a font to draw"),
      ),
      isEmpty,
    );
  });

  test(
    "writes recovery sheets to LEGACY_PDF_OUT for manual review",
    () async {
      final outputDir = Directory(Platform.environment["LEGACY_PDF_OUT"]!)
        ..createSync(recursive: true);
      final shares = [_share(1), _share(2), _share(3)];
      const service = LegacyKitPdfService();
      for (final share in shares) {
        final sheet = await service.buildRecoverySheet(
          accountEmail: "john@example.com",
          recoveryUrl: "https://legacy.ente.com",
          share: share,
          allShares: shares,
          strings: _strings,
        );
        final name = share.partName.toLowerCase();
        File(
          "${outputDir.path}/legacy-kit-${share.shareIndex}-$name.pdf",
        ).writeAsBytesSync(sheet);
      }
    },
    skip: Platform.environment["LEGACY_PDF_OUT"] == null
        ? "set LEGACY_PDF_OUT to a directory to write the sheets there"
        : null,
  );
}

Set<String> _embeddedFonts(List<int> pdf) {
  return RegExp(r"/BaseFont/([A-Za-z0-9-]+)")
      .allMatches(String.fromCharCodes(pdf))
      .map((match) => match.group(1)!)
      .toSet();
}

LegacyKitShare _share(int index) {
  final fixtures =
      jsonDecode(
            File(
              "../../../rust/crates/legacy/tests/fixtures/mobile-sheets.json",
            ).readAsStringSync(),
          )
          as List;
  final fixture = fixtures[index - 1] as Map<String, dynamic>;
  final qrPayload = fixture["qr_payload"] as String;
  final payload = jsonDecode(qrPayload) as Map<String, dynamic>;
  return LegacyKitShare(
    shareIndex: index,
    partName: payload["n"] as String,
    qrPayload: qrPayload,
    copyCode: fixture["copy_code"] as String,
  );
}
