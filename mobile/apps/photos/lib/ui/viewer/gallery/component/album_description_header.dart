import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class AlbumDescriptionHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const AlbumDescriptionHeader._({
    required this.description,
    required double height,
  }) : _height = height;

  static const maxLines = 3;

  final String description;
  final double _height;

  static AlbumDescriptionHeader? maybeOf(
    BuildContext context,
    String? description,
  ) {
    final normalizedDescription = description?.trim();
    if (normalizedDescription == null || normalizedDescription.isEmpty) {
      return null;
    }

    return AlbumDescriptionHeader._(
      description: normalizedDescription,
      height: preferredHeight(context, normalizedDescription),
    );
  }

  static double preferredHeight(BuildContext context, String? description) {
    final normalizedDescription = description?.trim();
    if (normalizedDescription == null || normalizedDescription.isEmpty) {
      return 0;
    }

    final painter = TextPainter(
      text: TextSpan(text: normalizedDescription, style: TextStyles.body),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - Spacing.lg * 2);
    return painter.height + Spacing.lg;
  }

  @override
  Size get preferredSize => Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            description,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
        ),
      ),
    );
  }
}
