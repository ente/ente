import "dart:async";

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";

class NewAlbumRowItemWidget extends StatelessWidget {
  static const _cornerRadius = 20.0;
  static const _thumbnailToTextSpacing = 8.0;

  final double height;
  final double width;
  final Future<void> Function(BuildContext context)? onTap;

  const NewAlbumRowItemWidget({
    super.key,
    required this.height,
    required this.width,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GestureDetector(
      onTap: onTap == null ? null : () => unawaited(onTap!(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(_cornerRadius),
            child: Container(
              height: height,
              width: width,
              color: colors.fillLight,
              child: Center(
                child: Image.asset(
                  "assets/new_album_icon.png",
                  width: 34,
                  height: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: _thumbnailToTextSpacing),
          Text(
            AppLocalizations.of(context).createAlbum,
            style: TextStyles.body.copyWith(color: colors.textLight),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
