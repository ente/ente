import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";

class SavePersonBanner extends StatelessWidget {
  final PersonFaceWidget faceWidget;
  final String text;
  final String subText;
  final Future<void> Function() onTap;

  const SavePersonBanner({
    super.key,
    required this.faceWidget,
    required this.text,
    required this.subText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: MenuItemWidgetNew(
        title: text,
        subText: subText,
        titleMaxLines: 1,
        subTextMaxLines: 1,
        subTextStyle: textTheme.miniMuted,
        titleToSubTextSpacing: 4,
        leadingIconSize: 36,
        leadingIconWidget: SizedBox.square(
          dimension: 36,
          child: FaceThumbnailSquircleClip(child: faceWidget),
        ),
        trailingWidget: SizedBox(
          width: 48,
          child: Icon(Icons.chevron_right, color: colorScheme.textBase),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
      ),
    );
  }
}
