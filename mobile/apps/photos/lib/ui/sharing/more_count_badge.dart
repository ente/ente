import 'package:flutter/material.dart';
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:tuple/tuple.dart';

enum MoreCountType { xs, small, medium, regular, large, huge }

class MoreCountWidget extends StatelessWidget {
  final MoreCountType type;
  final bool thumbnailView;
  final int count;
  final Color? backgroundColor;
  final Color? textColor;

  const MoreCountWidget(
    this.count, {
    super.key,
    this.type = MoreCountType.medium,
    this.thumbnailView = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final displayChar = "+$count";
    final Color decorationColor =
        backgroundColor ??
        (thumbnailView
            ? backgroundElevated2Light
            : colorScheme.backgroundElevated2);

    final avatarStyle = getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    final resolvedTextColor =
        textColor ??
        (thumbnailView && backgroundColor == null
            ? textBaseLight
            : Colors.white);
    final TextStyle textStyle = avatarStyle.item2.copyWith(
      color: resolvedTextColor,
    );
    return Container(
      padding: thumbnailView ? EdgeInsets.zero : const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: thumbnailView
            ? null
            : Border.all(
                color: getEnteColorScheme(context).strokeMuted,
                width: 1.0,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
      ),
      child: SizedBox(
        height: size,
        width: size,
        child: CircleAvatar(
          backgroundColor: decorationColor,
          child: Transform.scale(
            scale: 0.85,
            child: Text(
              displayChar.toUpperCase(),
              // fixed color
              style: textStyle,
            ),
          ),
        ),
      ),
    );
  }

  Tuple2<double, TextStyle> getAvatarStyle(
    BuildContext context,
    MoreCountType type,
  ) {
    final enteTextTheme = getEnteTextTheme(context);
    switch (type) {
      case MoreCountType.huge:
        return Tuple2(56.0, enteTextTheme.largeBold);
      case MoreCountType.large:
        return Tuple2(32.0, enteTextTheme.mini);
      case MoreCountType.regular:
        return Tuple2(28.0, enteTextTheme.mini);
      case MoreCountType.medium:
        return Tuple2(24.0, enteTextTheme.mini);
      case MoreCountType.small:
        return Tuple2(20.0, enteTextTheme.tiny);
      case MoreCountType.xs:
        return Tuple2(16.0, enteTextTheme.tiny);
    }
  }
}
