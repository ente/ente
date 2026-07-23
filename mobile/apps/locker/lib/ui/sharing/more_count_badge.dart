import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';

enum MoreCountType { small, mini, tiny, extra }

class MoreCountWidget extends StatelessWidget {
  final MoreCountType type;
  final bool thumbnailView;
  final int count;

  const MoreCountWidget(
    this.count, {
    super.key,
    this.type = MoreCountType.mini,
    this.thumbnailView = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final displayChar = "+$count";

    final Color decorationColor = colors.accentOrange;

    final avatarStyle = getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    final TextStyle textStyle = avatarStyle.item2.copyWith(
      color: colors.specialWhite,
    );

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.componentColors.fillLight,
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
            child: Text(displayChar.toUpperCase(), style: textStyle),
          ),
        ),
      ),
    );
  }

  Tuple2<double, TextStyle> getAvatarStyle(
    BuildContext context,
    MoreCountType type,
  ) {
    switch (type) {
      case MoreCountType.small:
        return const Tuple2(32.0, TextStyles.body);
      case MoreCountType.mini:
        return const Tuple2(24.0, TextStyles.mini);
      case MoreCountType.tiny:
        return const Tuple2(18.0, TextStyles.tiny);
      case MoreCountType.extra:
        return const Tuple2(18.0, TextStyles.tiny);
    }
  }
}
