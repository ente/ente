import "dart:math";

import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:flutter/material.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/sharing/more_count_badge.dart";

class AlbumSharesIcons extends StatelessWidget {
  final List<User> sharees;
  final int limitCountTo;
  final AvatarType type;
  final bool removeBorder;
  final EdgeInsets padding;
  final Widget? trailingWidget;
  final Alignment stackAlignment;

  const AlbumSharesIcons({
    super.key,
    required this.sharees,
    this.type = AvatarType.tiny,
    this.limitCountTo = 2,
    this.removeBorder = true,
    this.trailingWidget,
    this.padding = const EdgeInsets.only(left: 10.0, top: 10, bottom: 10),
    this.stackAlignment = Alignment.topLeft,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = min(sharees.length, limitCountTo);
    final hasMore = sharees.length > limitCountTo;
    final double overlapPadding = getOverlapPadding(type);
    final widgets = List<Widget>.generate(
      displayCount,
      (index) => Positioned(
        left: overlapPadding * index,
        child: UserAvatarWidget(
          sharees[index],
          thumbnailView: removeBorder,
          type: type,
          config: Configuration.instance,
        ),
      ),
    );

    if (hasMore) {
      widgets.add(
        Positioned(
          left: (overlapPadding * displayCount),
          child: MoreCountWidget(
            sharees.length - displayCount,
            type: moreCountTypeFromAvatarType(type),
            thumbnailView: removeBorder,
          ),
        ),
      );
    }
    if (trailingWidget != null) {
      widgets.add(
        Positioned(
          left:
              (overlapPadding * (displayCount + (hasMore ? 1 : 0))) +
              (displayCount > 0 ? 12 : 0),
          child: trailingWidget!,
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Stack(
        alignment: stackAlignment,
        clipBehavior: Clip.none,
        children: widgets,
      ),
    );
  }
}

double getOverlapPadding(AvatarType type) {
  switch (type) {
    case AvatarType.extra:
      return 14.0;
    case AvatarType.tiny:
      return 14.0;
    case AvatarType.mini:
      return 20.0;
    case AvatarType.small:
      return 28.0;
  }
}

MoreCountType moreCountTypeFromAvatarType(AvatarType type) {
  switch (type) {
    case AvatarType.extra:
      return MoreCountType.extra;
    case AvatarType.tiny:
      return MoreCountType.tiny;
    case AvatarType.mini:
      return MoreCountType.mini;
    case AvatarType.small:
      return MoreCountType.small;
  }
}
