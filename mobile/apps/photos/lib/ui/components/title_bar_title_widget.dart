import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';

class TitleBarTitleWidget extends StatelessWidget {
  static const _trailingActionSize = 38.0;

  final String? title;
  final bool isTitleH2;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? heroTag;
  final List<Widget>? trailingWidgets;
  const TitleBarTitleWidget({
    this.title,
    this.isTitleH2 = false,
    this.icon,
    this.onTap,
    this.heroTag,
    this.trailingWidgets,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorTheme = getEnteColorScheme(context);
    if (title != null) {
      late final Widget widget;
      if (icon != null) {
        widget = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              title!,
              style: textTheme.h3Bold,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 20, color: colorTheme.strokeMuted),
          ],
        );
      }
      if (isTitleH2) {
        widget = Text(
          title!,
          style: textTheme.h2Bold,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        );
      } else {
        widget = Text(
          title!,
          style: textTheme.h3Bold,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        );
      }

      if (trailingWidgets != null && trailingWidgets!.isNotEmpty) {
        return Row(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: heroTag != null
                    ? Hero(tag: heroTag!, child: widget)
                    : widget,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _trailingActionSize,
                minHeight: _trailingActionSize,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: trailingWidgets!,
                ),
              ),
            ),
          ],
        );
      }

      return GestureDetector(
        onTap: onTap,
        child: heroTag != null ? Hero(tag: heroTag!, child: widget) : widget,
      );
    }

    return const SizedBox.shrink();
  }
}
