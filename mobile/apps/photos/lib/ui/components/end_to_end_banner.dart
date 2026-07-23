import "package:flutter/material.dart";
import "package:photos/models/typedefs.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";

class EndToEndBanner extends StatelessWidget {
  final String? title;
  final String? caption;
  final IconData? leadingIcon;
  final FutureVoidCallback? onTap;
  final Widget? trailingWidget;
  const EndToEndBanner({
    this.title,
    this.caption,
    this.leadingIcon,
    this.onTap,
    this.trailingWidget,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: colorScheme.fillFaint,
        padding: EdgeInsets.fromLTRB(16, 8, trailingWidget != null ? 16 : 0, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                leadingIcon != null
                    ? Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.backdropBase,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(leadingIcon!, size: 28),
                      )
                    : const SizedBox.shrink(),
                leadingIcon != null
                    ? const SizedBox(width: 12)
                    : const SizedBox.shrink(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title != null
                        ? Text(title!, style: textTheme.bodyBold)
                        : const SizedBox.shrink(),
                    title != null && caption != null
                        ? const SizedBox(height: 4)
                        : const SizedBox.shrink(),
                    caption != null
                        ? Text(caption!, style: textTheme.miniMuted)
                        : const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
            trailingWidget == null
                ? const IconButtonWidget(
                    icon: Icons.chevron_right,
                    iconButtonType: IconButtonType.primary,
                  )
                : trailingWidget!,
          ],
        ),
      ),
    );
  }
}
