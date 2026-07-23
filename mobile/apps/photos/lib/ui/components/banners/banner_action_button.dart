import "package:flutter/material.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";

enum BannerActionButtonVariant { neutral, primary }

class BannerActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final BannerActionButtonVariant variant;
  final bool showTag;
  final bool stickTagToLightTheme;

  const BannerActionButton({
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.variant = BannerActionButtonVariant.neutral,
    this.showTag = false,
    this.stickTagToLightTheme = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final tagLabel = context.l10n.offlineEnableBackupTagLabel;
    final resolvedBackgroundColor = switch (variant) {
      BannerActionButtonVariant.neutral => fillLight,
      BannerActionButtonVariant.primary => green,
    };
    final resolvedForegroundColor = switch (variant) {
      BannerActionButtonVariant.neutral => contentLight,
      BannerActionButtonVariant.primary => contentDark,
    };
    final buttonTextStyle = textTheme.smallBold.copyWith(
      color: resolvedForegroundColor,
      fontWeight: FontWeight.w700,
    );

    final resolvedTagBackgroundColor = stickTagToLightTheme
        ? fillLight
        : colorScheme.fillReverse;
    final resolvedTagForegroundColor = stickTagToLightTheme
        ? contentLight
        : colorScheme.contentReverse;
    final tagTextStyle = textTheme.miniBold.copyWith(
      color: resolvedTagForegroundColor,
      fontWeight: FontWeight.w900,
      fontFamily: "Nunito",
      fontSize: 9,
      height: 11 / 9,
    );

    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: resolvedBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: buttonTextStyle, textAlign: TextAlign.center),
      ),
    );

    if (!showTag) {
      return button;
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: -17,
          right: -18,
          child: Transform.rotate(
            angle: 0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: resolvedTagBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(tagLabel, style: tagTextStyle),
            ),
          ),
        ),
        button,
      ],
    );
  }
}
