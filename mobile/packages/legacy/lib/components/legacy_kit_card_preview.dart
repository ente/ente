import "package:ente_components/ente_components.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/services/legacy_kit_pdf_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";

const _cardBorder = Color(0xFFE0E0E0);
const _cardMutedInk = Color(0xFF969696);
const _chipInk = Color(0xFF666666);
const _chipFill = Color(0xFFEAEAEA);
const _holderRed = Color(0xFFF24822);

class LegacyKitCardPreview extends StatelessWidget {
  final LegacyKit kit;
  final LegacyKitPart part;

  const LegacyKitCardPreview({
    required this.kit,
    required this.part,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final otherParts = kit.parts
        .where((other) => other.index != part.index)
        .toList(growable: false);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: _cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SvgPicture.asset(
                      "assets/legacy_kit_sheet_logo.svg",
                      package: "ente_legacy",
                      height: 17,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "Legacy Kit",
                      style: TextStyle(
                        fontFamily: "Nunito",
                        package: "ente_legacy",
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(0xFF1C1C1C),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 111,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SvgPicture.asset(
                        "assets/legacy_kit_qr.svg",
                        package: "ente_legacy",
                        width: 111,
                        height: 111,
                      ),
                      _GoToPill(
                        url: LegacyKitPdfService.displayRecoveryUrl(
                          kit.legacyUrl,
                        ),
                        linkColor: colors.blue,
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Center(
                      child: Text(
                        context.strings.getAnotherPartOfKitFrom,
                        style: TextStyles.mini.copyWith(color: _cardMutedInk),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < otherParts.length; i++) ...[
                          if (i > 0) const SizedBox(width: Spacing.xs),
                          _HolderChip(
                            name: otherParts[i].name,
                            color: i == 0 ? colors.blue : _holderRed,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoToPill extends StatelessWidget {
  final String url;
  final Color linkColor;

  const _GoToPill({required this.url, required this.linkColor});

  Future<void> _copyUrl(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      showShortToast(context, context.strings.linkCopiedToClipboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.strings.goToUrl(url);
    final urlStart = text.indexOf(url);
    final prefix = urlStart <= 0 ? "" : text.substring(0, urlStart);
    final suffix = urlStart < 0 ? "" : text.substring(urlStart + url.length);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _copyUrl(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Spacing.md, 5, Spacing.md, 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(Radii.sm),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40497CC9),
              offset: Offset(0, 4),
              blurRadius: 15,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedLink02,
              color: _chipInk,
              size: 12,
            ),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (prefix.isNotEmpty)
                      TextSpan(
                        text: prefix,
                        style: TextStyles.mini.copyWith(color: _cardMutedInk),
                      ),
                    TextSpan(
                      text: url,
                      style: TextStyles.mini.copyWith(color: linkColor),
                    ),
                    if (suffix.isNotEmpty)
                      TextSpan(
                        text: suffix,
                        style: TextStyles.mini.copyWith(color: _cardMutedInk),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HolderChip extends StatelessWidget {
  final String name;
  final Color color;

  const _HolderChip({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final trimmed = name.trim();
    final chars = trimmed.characters;
    final initial = chars.isEmpty ? "?" : chars.first.toUpperCase();
    final displayName = chars.length > 5 ? "${chars.take(5)}…" : trimmed;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, Spacing.sm, 3),
      decoration: const BoxDecoration(
        color: _chipFill,
        borderRadius: BorderRadius.all(Radius.circular(Radii.button)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                initial,
                style: TextStyles.tiny.copyWith(color: colors.specialWhite),
              ),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Text(displayName, style: TextStyles.tiny.copyWith(color: _chipInk)),
        ],
      ),
    );
  }
}
