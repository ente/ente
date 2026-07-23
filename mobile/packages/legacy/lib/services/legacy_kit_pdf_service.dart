import "dart:convert";

import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;

class LegacyKitPdfService {
  const LegacyKitPdfService();

  static const String _shareMetadataPrefix = "ente-legacy-kit-share-v1:";
  static const String _assetRoot = "packages/ente_legacy/assets";
  static const String _logoAsset = "$_assetRoot/legacy_kit_sheet_logo.svg";
  static const String _enteLogoBlackAsset =
      "$_assetRoot/legacy_kit_sheet_ente_logo_black.svg";
  static const String _enteComBadgeAsset =
      "$_assetRoot/legacy_kit_sheet_ente_com_badge.svg";
  static const String _nunitoExtraBoldAsset =
      "$_assetRoot/fonts/Nunito-ExtraBold.ttf";
  static const String _nunitoBlackAsset = "$_assetRoot/fonts/Nunito-Black.ttf";
  static const String _interRegularAsset = "assets/fonts/Inter-Regular.ttf";
  static const String _interMediumAsset = "assets/fonts/Inter-Medium.ttf";
  static const String _interBoldAsset = "assets/fonts/Inter-Bold.ttf";

  static const PdfPageFormat _sheetPageFormat = PdfPageFormat(676, 900);
  static const PdfColor _green = PdfColor.fromInt(0xFF08C225);
  static const PdfColor _dark = PdfColor.fromInt(0xFF212121);
  static const PdfColor _black = PdfColor.fromInt(0xFF000000);
  static const PdfColor _white = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _card = PdfColor.fromInt(0xFFEAEAEA);
  static const PdfColor _divider = PdfColor.fromInt(0xFFD9D9D9);
  static const PdfColor _stepNumber = PdfColor.fromInt(0xFF5B5B5B);
  static const PdfColor _bodyText = PdfColor(0, 0, 0, 0.86);
  static const PdfColor _chipBackground = PdfColor.fromInt(0xFF484848);
  static const PdfColor _chipLabel = PdfColor.fromInt(0xFFF4F4F4);
  static const PdfColor _copyCodeBackground = PdfColor.fromInt(0xFF666666);
  static const List<PdfColor> _holderChipColors = [
    PdfColor.fromInt(0xFFFF6060),
    PdfColor.fromInt(0xFF1EA8FE),
  ];

  Future<Uint8List> buildRecoverySheet({
    required String accountEmail,
    required String recoveryUrl,
    required LegacyKitShare share,
    required List<LegacyKitShare> allShares,
  }) async {
    final assets = await _loadAssets();
    final sortedShares = _sortedShares(allShares);
    final pdf = _document(keywords: _shareMetadata(share));
    pdf.addPage(
      _buildPage(accountEmail, recoveryUrl, share, sortedShares, assets),
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
    final nunitoExtraBold = await _loadFont(_nunitoExtraBoldAsset);
    final nunitoBlack = await _loadFont(_nunitoBlackAsset);
    final baseFont = interMedium ?? interRegular;

    return _SheetAssets(
      logoSvg: await _loadSvg(_logoAsset),
      enteLogoBlackSvg: await _loadSvg(_enteLogoBlackAsset),
      enteComBadgeSvg: await _loadSvg(_enteComBadgeAsset),
      nunitoExtraBold: nunitoExtraBold ?? nunitoBlack,
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
          assets: assets,
        );
      },
    );
  }

  pw.Widget _buildSheet({
    required String accountEmail,
    required String recoveryUrl,
    required LegacyKitShare share,
    required List<LegacyKitShare> otherShares,
    required _SheetAssets assets,
  }) {
    final qrPayload = share.toQrPayload();
    final copyCode = share.toCopyCode();
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
              top: 135,
              child: pw.Container(
                width: 654,
                height: 752,
                decoration: const pw.BoxDecoration(
                  color: _card,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(24)),
                ),
              ),
            ),
            pw.Positioned(left: 269, top: 52, child: _header(assets)),
            pw.Positioned(
              left: 84,
              top: 178,
              child: _accountEmailPill(accountEmail, assets),
            ),
            pw.Positioned(
              left: 84,
              top: 223,
              child: pw.SizedBox(
                width: 506,
                // Holder names are unbounded, so the greeting can wrap. The
                // description follows it in flow instead of at a fixed offset.
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 451,
                      child: pw.Text(
                        "Hi ${share.partName}, store this somewhere safe",
                        maxLines: 2,
                        style: pw.TextStyle(
                          color: _black,
                          fontSize: 21,
                          font: assets.nunitoExtraBold,
                          fontWeight: pw.FontWeight.bold,
                          lineSpacing: 5,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 22),
                    pw.Text(
                      "You can use this with any other part to get access to my "
                      "Ente account that contains important information.",
                      style: const pw.TextStyle(
                        color: _bodyText,
                        fontSize: 14.4,
                        lineSpacing: 6.5,
                      ),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Container(
                      width: 504,
                      height: 2,
                      // A pill radius is clamped by Flutter but not by the PDF
                      // renderer, which would balloon this 2pt rule into a blob.
                      decoration: const pw.BoxDecoration(
                        color: _divider,
                        borderRadius: pw.BorderRadius.all(
                          pw.Radius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.Positioned(
              left: 90,
              top: 386,
              child: pw.Text(
                "How to recover the account?",
                style: pw.TextStyle(
                  color: _black,
                  fontSize: 27,
                  font: assets.nunitoExtraBold,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Positioned(
              left: 87,
              top: 451,
              child: _step(
                "1",
                pw.Text(
                  "Get another part from",
                  style: const pw.TextStyle(color: _black, fontSize: 14),
                ),
                trailing: _holderChips(otherShares),
              ),
            ),
            pw.Positioned(
              left: 87,
              top: 512,
              child: _step("2", _visitLabel(recoveryUrl)),
            ),
            pw.Positioned(left: 217, top: 573, child: _qrCard(qrPayload)),
            if (kDebugMode)
              pw.Positioned(
                left: 217,
                top: 831,
                child: _copyCodeBlock(copyCode),
              ),
            pw.Positioned(left: 573, top: 812, child: _enteLockup(assets)),
            pw.Positioned(
              left: 504,
              top: 845,
              child: pw.Text(
                "Protect your digital life",
                style: pw.TextStyle(
                  color: _black,
                  fontSize: 12.6,
                  font: assets.nunitoExtraBold,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _accountEmailPill(String accountEmail, _SheetAssets assets) {
    return pw.Container(
      width: 200,
      height: 29,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12),
      decoration: const pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(11)),
      ),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        child: pw.Text(
          accountEmail,
          maxLines: 1,
          style: pw.TextStyle(
            color: _black,
            fontSize: 16.4,
            font: assets.nunitoExtraBold,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  pw.Widget _qrCard(String qrPayload) {
    return pw.Container(
      width: 242,
      height: 242,
      padding: const pw.EdgeInsets.all(28),
      decoration: const pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(24)),
      ),
      child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrPayload),
    );
  }

  pw.Widget _step(String number, pw.Widget label, {pw.Widget? trailing}) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
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
        label,
        if (trailing != null) ...[pw.SizedBox(width: 24), trailing],
      ],
    );
  }

  pw.Widget _visitLabel(String recoveryUrl) {
    return pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(color: _black, fontSize: 14),
        children: [
          const pw.TextSpan(text: "Visit "),
          pw.TextSpan(
            text: displayRecoveryUrl(recoveryUrl),
            style: const pw.TextStyle(
              color: _black,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ],
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
      width: 82,
      height: 38,
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
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  )
                : pw.SizedBox(
                    width: 75.7,
                    height: 22.5,
                    child: pw.SvgImage(svg: enteLogoSvg),
                  ),
          ),
          pw.Positioned(
            left: 44,
            top: 20,
            child: enteComBadgeSvg == null
                ? pw.Container(
                    width: 37,
                    height: 16,
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
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : pw.SizedBox(
                    width: 36.7,
                    height: 16.1,
                    child: pw.SvgImage(svg: enteComBadgeSvg),
                  ),
          ),
        ],
      ),
    );
  }

  pw.Widget _header(_SheetAssets assets) {
    final logoSvg = assets.logoSvg;
    final enteLogoSvg = assets.enteLogoBlackSvg;
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: logoSvg == null
              ? _fallbackHeaderLogo()
              : pw.SizedBox(
                  width: 29.4,
                  height: 30.4,
                  child: pw.SvgImage(svg: logoSvg),
                ),
        ),
        pw.SizedBox(width: 10.6),
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            enteLogoSvg == null
                ? pw.Text(
                    "ente",
                    style: pw.TextStyle(
                      color: _dark,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  )
                : pw.SizedBox(
                    width: 44,
                    height: 13.1,
                    child: pw.SvgImage(svg: enteLogoSvg),
                  ),
            pw.SizedBox(height: 4),
            pw.Text(
              "Legacy Kit",
              style: pw.TextStyle(
                color: const PdfColor.fromInt(0xFF1C1C1C),
                fontSize: 20,
                font: assets.nunitoExtraBold,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _fallbackHeaderLogo() {
    return pw.Container(
      width: 29,
      height: 29,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _black, width: 1.6),
        shape: pw.BoxShape.circle,
      ),
      child: pw.Center(
        child: pw.Text(
          "e",
          style: pw.TextStyle(
            color: _black,
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
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
    final compactCode = copyCode.replaceAll(RegExp(r"\s+"), "");
    final chunks = <String>[];
    for (var index = 0; index < compactCode.length; index += chunkSize) {
      final nextIndex = index + chunkSize;
      final end = nextIndex > compactCode.length
          ? compactCode.length
          : nextIndex;
      chunks.add(compactCode.substring(index, end));
    }
    return chunks;
  }

  pw.Widget _holderChips(List<LegacyKitShare> shares) {
    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: shares
          .asMap()
          .entries
          .map((entry) => _holderChip(entry.value, entry.key))
          .toList(growable: false),
    );
  }

  pw.Widget _holderChip(LegacyKitShare share, int chipIndex) {
    final initial = share.partName.trim().isEmpty
        ? "?"
        : share.partName.trim()[0].toUpperCase();
    final chipColor = _holderChipColors[chipIndex % _holderChipColors.length];
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: const pw.BoxDecoration(
        color: _chipBackground,
        // The PDF renderer does not clamp pill radii like Flutter does.
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(16)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 24,
            height: 24,
            decoration: pw.BoxDecoration(
              color: chipColor,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                initial,
                style: const pw.TextStyle(color: _white, fontSize: 12),
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            share.partName,
            style: const pw.TextStyle(color: _chipLabel, fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<LegacyKitShare> _sortedShares(List<LegacyKitShare> shares) {
    return shares.toList(growable: false)
      ..sort((a, b) => a.shareIndex.compareTo(b.shareIndex));
  }
}

class _SheetAssets {
  final String? logoSvg;
  final String? enteLogoBlackSvg;
  final String? enteComBadgeSvg;
  final pw.Font? nunitoExtraBold;
  final pw.ThemeData? theme;

  const _SheetAssets({
    required this.logoSvg,
    required this.enteLogoBlackSvg,
    required this.enteComBadgeSvg,
    required this.nunitoExtraBold,
    required this.theme,
  });
}
