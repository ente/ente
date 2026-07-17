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

  test("normalizes compact legacy kit payload fields", () {
    final payload =
        jsonDecode(
              const LegacyKitShare(
                payloadVersion: 1,
                variant: 1,
                kitId: " e04efa62-2607-4c8b-b4c7-6c84f08fe162 ",
                shareIndex: 2,
                share: "USpH7sFwOXQ/TeSu1BeAJqfeVxwlKXZLnlCZ mOfmQiY=",
                checksum: " c1T4uxBh7ws= ",
                partName: "Amit, Brother, 98",
              ).toQrPayload(),
            )
            as Map<String, dynamic>;

    expect(payload["k"], "e04efa62-2607-4c8b-b4c7-6c84f08fe162");
    expect(payload["s"], "USpH7sFwOXQ/TeSu1BeAJqfeVxwlKXZLnlCZmOfmQiY=");
    expect(payload["c"], "c1T4uxBh7ws=");
    expect(payload["n"], "Amit, Brother, 98");
  });

  test("encodes compact payload as copy code", () {
    final share = _share(1, "Mom");
    expect(
      utf8.decode(base64Url.decode(base64Url.normalize(share.toCopyCode()))),
      share.toQrPayload(),
    );
  });

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
    final shares = [_share(1, "Mom"), _share(2, "Alex"), _share(3, "Lawyer")];

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
      expect(
        _metadataPayload(sheets[index], "ente-legacy-kit-share-v1:"),
        shares[index].toQrPayload(),
      );
    }
  });

  test(
    "embeds the sheet fonts instead of falling back to a base font",
    () async {
      final shares = [_share(1, "Mom"), _share(2, "Alex")];
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
          "Inter-Regular",
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

  test(
    "writes recovery sheets to LEGACY_PDF_OUT for manual review",
    () async {
      final outputDir = Directory(Platform.environment["LEGACY_PDF_OUT"]!)
        ..createSync(recursive: true);
      final shares = [_share(1, "Mom"), _share(2, "Alex"), _share(3, "Lawyer")];
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

String _metadataPayload(List<int> pdf, String prefix) {
  final text = String.fromCharCodes(pdf);
  final encoded = RegExp("$prefix([A-Za-z0-9_-]+)").firstMatch(text)!.group(1)!;
  return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
}

LegacyKitShare _share(int index, String partName) {
  return LegacyKitShare(
    payloadVersion: 1,
    variant: 1,
    kitId: "kit-id",
    shareIndex: index,
    share: "AQEgx7Kp2mNfR4wBzH8vTjYdLnUcXsS6aWe3qFh9iDlOkPr0tMbJ4vG$index",
    checksum: "checksum",
    partName: partName,
  );
}
