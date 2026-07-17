import "dart:convert";

import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;

class LegacyKitPdfService {
  const LegacyKitPdfService();

  static const String _shareMetadataPrefix = "ente-legacy-kit-share-v1:";
  static const String _assetRoot = "packages/ente_legacy/assets";
  static const String _fontRoot = "packages/ente_components/fonts";
  static const String _enteLogoBlackAsset =
      "$_assetRoot/legacy_kit_sheet_ente_logo_black.svg";
  static const String _enteComBadgeAsset =
      "$_assetRoot/legacy_kit_sheet_ente_com_badge.svg";
  static const String _interRegularAsset = "$_fontRoot/Inter-Regular.ttf";
  static const String _interMediumAsset = "$_fontRoot/Inter-Medium.ttf";
  static const String _interBoldAsset = "$_fontRoot/Inter-Bold.ttf";
  static const String _outfitSemiBoldAsset = "$_fontRoot/Outfit-SemiBold.ttf";

  static const String _supportEmail = "support@ente.com";
  static const int _sheetsNeededToRecover = 2;
  static const String _emphasisSlot = "\uFFFC";

  static const PdfPageFormat _sheetPageFormat = PdfPageFormat(676, 900);
  static const PdfColor _green = PdfColor.fromInt(0xFF08C225);
  static const PdfColor _dark = PdfColor.fromInt(0xFF212121);
  static const PdfColor _black = PdfColor.fromInt(0xFF000000);
  static const PdfColor _white = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _card = PdfColor.fromInt(0xFFEAEAEA);
  static const PdfColor _divider = PdfColor.fromInt(0xFFD9D9D9);
  static const PdfColor _stepNumber = PdfColor.fromInt(0xFF5B5B5B);
  static const PdfColor _copyCodeBackground = PdfColor.fromInt(0xFF666666);

  Future<Uint8List> buildRecoverySheet({
    required String accountEmail,
    required String recoveryUrl,
    required LegacyKitShare share,
    required List<LegacyKitShare> allShares,
    required StringsLocalizations strings,
  }) async {
    final assets = await _loadAssets();
    final sortedShares = _sortedShares(allShares);
    final pdf = _document(keywords: _shareMetadata(share));
    pdf.addPage(
      _buildPage(
        accountEmail,
        recoveryUrl,
        share,
        sortedShares,
        assets,
        strings,
      ),
    );
    return pdf.save();
  }

  static String displayRecoveryUrl(String recoveryUrl) {
    final normalized = recoveryUrl.trim().replaceFirst(RegExp(r"/+$"), "");
    if (normalized.isEmpty) {
      return "legacy.ente.com";
    }
    return normalized.replaceFirst(RegExp(r"^https?://"), "");
  }

  Future<_SheetAssets> _loadAssets() async {
    final interRegular = await _loadFont(_interRegularAsset);
    final interMedium = await _loadFont(_interMediumAsset);
    final interBold = await _loadFont(_interBoldAsset);
    final outfitSemiBold = await _loadFont(_outfitSemiBoldAsset);
    final baseFont = interMedium ?? interRegular;

    return _SheetAssets(
      enteLogoBlackSvg: await _loadSvg(_enteLogoBlackAsset),
      enteComBadgeSvg: await _loadSvg(_enteComBadgeAsset),
      outfitSemiBold: outfitSemiBold,
      interRegular: interRegular ?? baseFont,
      theme: baseFont == null && interBold == null
          ? null
          : pw.ThemeData.withFont(base: baseFont, bold: interBold ?? baseFont),
    );
  }

  Future<String?> _loadSvg(String asset) async {
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      return null;
    }
  }

  Future<pw.Font?> _loadFont(String asset) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } catch (_) {
      return null;
    }
  }

  pw.Document _document({required String keywords}) {
    return pw.Document(
      title: "Ente Legacy Kit",
      author: "ente",
      creator: "ente locker",
      subject: "Ente Legacy Kit recovery sheet",
      keywords: keywords,
      producer: "ente locker",
    );
  }

  String _shareMetadata(LegacyKitShare share) {
    return "$_shareMetadataPrefix${_encodeMetadataPayload(share.toQrPayload())}";
  }

  String _encodeMetadataPayload(String payload) {
    return base64Url.encode(utf8.encode(payload)).replaceAll("=", "");
  }

  pw.Page _buildPage(
    String accountEmail,
    String recoveryUrl,
    LegacyKitShare share,
    List<LegacyKitShare> sortedShares,
    _SheetAssets assets,
    StringsLocalizations strings,
  ) {
    return pw.Page(
      pageFormat: _sheetPageFormat,
      margin: pw.EdgeInsets.zero,
      theme: assets.theme,
      build: (context) {
        final otherShares = sortedShares
            .where((item) => item.shareIndex != share.shareIndex)
            .toList(growable: false);
        return _buildSheet(
          accountEmail: accountEmail,
          recoveryUrl: recoveryUrl,
          share: share,
          otherShares: otherShares,
          totalSheets: sortedShares.length,
          assets: assets,
          strings: strings,
        );
      },
    );
  }

  pw.Widget _buildSheet({
    required String accountEmail,
    required String recoveryUrl,
    required LegacyKitShare share,
    required List<LegacyKitShare> otherShares,
    required int totalSheets,
    required _SheetAssets assets,
    required StringsLocalizations strings,
  }) {
    final qrPayload = share.toQrPayload();
    return pw.SizedBox(
      width: _sheetPageFormat.width,
      height: _sheetPageFormat.height,
      child: pw.Container(
        color: _white,
        child: pw.Stack(
          fit: pw.StackFit.expand,
          children: [
            pw.Positioned(
              left: 11,
              top: 95,
              child: pw.Container(
                width: 654,
                height: 742,
                decoration: const pw.BoxDecoration(
                  color: _card,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(24)),
                ),
              ),
            ),
            pw.Positioned(
              left: 57,
              top: 29,
              child: _accountEmailPill(accountEmail, assets),
            ),
            pw.Positioned(left: 593.5, top: 29, child: _enteLockup(assets)),
            pw.Positioned(
              left: 538,
              top: 56,
              child: pw.Text(
                "Protect your digital life",
                style: pw.TextStyle(
                  color: _black,
                  fontSize: 10.8,
                  font: assets.outfitSemiBold,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Positioned(
              left: 80,
              top: 136,
              child: _greeting(
                strings.legacyKitSheetGreeting(share.partName),
                assets,
              ),
            ),
            pw.Positioned(
              left: 81,
              top: 195,
              child: pw.SizedBox(
                width: 506,
                child: pw.Text(
                  strings.legacyKitSheetIntro,
                  style: const pw.TextStyle(
                    color: _black,
                    fontSize: 14.4,
                    lineSpacing: -1.4,
                  ),
                ),
              ),
            ),
            pw.Positioned(
              left: 67,
              top: 253,
              child: pw.Container(
                width: 541,
                height: 2,
                // A pill radius is clamped by Flutter but not by the PDF
                // renderer, which would balloon this 2pt rule into a blob.
                decoration: const pw.BoxDecoration(
                  color: _divider,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(1)),
                ),
              ),
            ),
            pw.Positioned(
              left: 81,
              top: 275,
              child: pw.Text(
                strings.legacyKitSheetHowToRecover,
                style: pw.TextStyle(
                  color: _black,
                  fontSize: 27,
                  font: assets.outfitSemiBold,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Positioned(
              left: 88,
              top: 344,
              child: _steps(
                share,
                otherShares,
                totalSheets,
                recoveryUrl,
                strings,
              ),
            ),
            pw.Positioned(left: 92.6, top: 533, child: _qrCard(qrPayload)),
            pw.Positioned(
              left: 92.6,
              top: 791,
              child: pw.SizedBox(
                width: 242.5,
                child: pw.Text(
                  strings.legacyKitSheetScanAt(displayRecoveryUrl(recoveryUrl)),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    color: _black,
                    fontSize: 14,
                    font: assets.interRegular,
                  ),
                ),
              ),
            ),
            if (kDebugMode)
              pw.Positioned(
                left: 360,
                top: 533,
                child: _copyCodeBlock(share.toCopyCode()),
              ),
            pw.Positioned(
              left: 0,
              top: 860,
              child: pw.SizedBox(
                width: _sheetPageFormat.width,
                child: _supportLabel(strings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _accountEmailPill(String accountEmail, _SheetAssets assets) {
    return pw.Container(
      height: 45,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 25),
      decoration: const pw.BoxDecoration(
        color: _card,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(15)),
      ),
      child: pw.ConstrainedBox(
        constraints: const pw.BoxConstraints(maxWidth: 430),
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            accountEmail,
            maxLines: 1,
            style: pw.TextStyle(
              color: _black,
              fontSize: 20,
              font: assets.outfitSemiBold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _greeting(String greeting, _SheetAssets assets) {
    return pw.SizedBox(
      width: 565,
      height: 46,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          greeting,
          maxLines: 1,
          style: pw.TextStyle(
            color: _black,
            fontSize: 32.2,
            font: assets.outfitSemiBold,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  pw.Widget _qrCard(String qrPayload) {
    return pw.Container(
      width: 242.5,
      height: 242.5,
      padding: const pw.EdgeInsets.all(28),
      decoration: const pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(24)),
      ),
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: qrPayload,
        drawText: false,
      ),
    );
  }

  pw.Widget _steps(
    LegacyKitShare share,
    List<LegacyKitShare> otherShares,
    int totalSheets,
    String recoveryUrl,
    StringsLocalizations strings,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _step("1", _otherSheetsLabel(share, otherShares, totalSheets, strings)),
        pw.SizedBox(height: 29),
        _step("2", _visitLabel(recoveryUrl, strings)),
        pw.SizedBox(height: 36),
        _step(
          "3",
          pw.Text(
            strings.legacyKitSheetStepScan(_sheetsNeededToRecover),
            style: const pw.TextStyle(color: _black, fontSize: 14),
          ),
        ),
      ],
    );
  }

  pw.Widget _step(String number, pw.Widget label) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 24,
          height: 24,
          decoration: const pw.BoxDecoration(
            color: _divider,
            shape: pw.BoxShape.circle,
          ),
          child: pw.Center(
            child: pw.Text(
              number,
              style: const pw.TextStyle(color: _stepNumber, fontSize: 14),
            ),
          ),
        ),
        pw.SizedBox(width: 16),
        pw.SizedBox(width: 446, child: label),
      ],
    );
  }

  pw.Widget _otherSheetsLabel(
    LegacyKitShare share,
    List<LegacyKitShare> otherShares,
    int totalSheets,
    StringsLocalizations strings,
  ) {
    return pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(color: _black, fontSize: 14, lineSpacing: 5),
        children: _spansAroundSlot(
          strings.legacyKitSheetStepGetAnother(
            share.shareIndex,
            totalSheets,
            _emphasisSlot,
          ),
          _holderNameSpans(otherShares, strings),
        ),
      ),
    );
  }

  List<pw.TextSpan> _spansAroundSlot(
    String sentence,
    List<pw.TextSpan> emphasis,
  ) {
    final parts = sentence.split(_emphasisSlot);
    return [
      pw.TextSpan(text: parts.first),
      ...emphasis,
      if (parts.length > 1)
        pw.TextSpan(text: parts.sublist(1).join(_emphasisSlot)),
    ];
  }

  List<pw.TextSpan> _holderNameSpans(
    List<LegacyKitShare> otherShares,
    StringsLocalizations strings,
  ) {
    final spans = <pw.TextSpan>[];
    for (var index = 0; index < otherShares.length; index++) {
      if (index > 0) {
        spans.add(
          pw.TextSpan(
            text: index == otherShares.length - 1
                ? strings.legacyKitSheetNameJoinerOr
                : strings.legacyKitSheetNameJoinerList,
          ),
        );
      }
      spans.add(
        pw.TextSpan(
          text: otherShares[index].partName,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      );
    }
    return spans;
  }

  pw.Widget _visitLabel(String recoveryUrl, StringsLocalizations strings) {
    return pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(color: _black, fontSize: 14),
        children:
            _spansAroundSlot(strings.legacyKitSheetStepVisit(_emphasisSlot), [
              pw.TextSpan(
                text: displayRecoveryUrl(recoveryUrl),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ]),
      ),
    );
  }

  pw.Widget _supportLabel(StringsLocalizations strings) {
    return pw.RichText(
      textAlign: pw.TextAlign.center,
      text: pw.TextSpan(
        style: const pw.TextStyle(color: _black, fontSize: 11.9),
        children: _spansAroundSlot(
          strings.legacyKitSheetNeedHelp(_emphasisSlot),
          const [
            pw.TextSpan(
              text: _supportEmail,
              style: pw.TextStyle(decoration: pw.TextDecoration.underline),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _copyCodeBlock(String copyCode) {
    return pw.Container(
      width: 242,
      height: 56,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: _copyCodeBackground,
        border: pw.Border.all(
          color: _white,
          width: 1,
          style: pw.BorderStyle.dashed,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Center(child: _copyCodeText(copyCode)),
    );
  }

  pw.Widget _enteLockup(_SheetAssets assets) {
    final enteLogoSvg = assets.enteLogoBlackSvg;
    final enteComBadgeSvg = assets.enteComBadgeSvg;
    return pw.SizedBox(
      width: 56,
      height: 26,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            top: 0,
            child: enteLogoSvg == null
                ? pw.Text(
                    "ente",
                    style: pw.TextStyle(
                      color: _dark,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  )
                : pw.SizedBox(
                    width: 51.9,
                    height: 15.4,
                    child: pw.SvgImage(svg: enteLogoSvg),
                  ),
          ),
          pw.Positioned(
            left: 30.3,
            top: 14,
            child: enteComBadgeSvg == null
                ? pw.Container(
                    width: 25.2,
                    height: 11.1,
                    decoration: const pw.BoxDecoration(
                      color: _green,
                      borderRadius: pw.BorderRadius.all(
                        pw.Radius.circular(999),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        ".com",
                        style: pw.TextStyle(
                          color: _dark,
                          fontSize: 5.1,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : pw.SizedBox(
                    width: 25.2,
                    height: 11.1,
                    child: pw.SvgImage(svg: enteComBadgeSvg),
                  ),
          ),
        ],
      ),
    );
  }

  pw.Widget _copyCodeText(String copyCode) {
    return pw.SizedBox(
      width: 226,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: _displayCopyCodeLines(copyCode)
            .map(
              (line) => pw.SizedBox(
                height: 11,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    line,
                    textAlign: pw.TextAlign.center,
                    softWrap: false,
                    maxLines: 1,
                    style: pw.TextStyle(
                      color: _white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  List<String> _displayCopyCodeLines(String copyCode) {
    const chunkSize = 33;
    final chunks = <String>[];
    for (var index = 0; index < copyCode.length; index += chunkSize) {
      final nextIndex = index + chunkSize;
      final end = nextIndex > copyCode.length ? copyCode.length : nextIndex;
      chunks.add(copyCode.substring(index, end));
    }
    return chunks;
  }

  List<LegacyKitShare> _sortedShares(List<LegacyKitShare> shares) {
    return shares.toList(growable: false)
      ..sort((a, b) => a.shareIndex.compareTo(b.shareIndex));
  }
}

class _SheetAssets {
  final String? enteLogoBlackSvg;
  final String? enteComBadgeSvg;
  final pw.Font? outfitSemiBold;
  final pw.Font? interRegular;
  final pw.ThemeData? theme;

  const _SheetAssets({
    required this.enteLogoBlackSvg,
    required this.enteComBadgeSvg,
    required this.outfitSemiBold,
    required this.interRegular,
    required this.theme,
  });
}
