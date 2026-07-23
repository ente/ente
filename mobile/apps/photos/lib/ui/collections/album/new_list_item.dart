import "dart:async";

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";

class NewAlbumListItemWidget extends StatelessWidget {
  final Future<void> Function(BuildContext context)? onTap;

  const NewAlbumListItemWidget({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return ThumbnailListItem(
      backgroundColor: thumbnailListItemBackgroundColor(context),
      onTap: onTap == null ? null : () => unawaited(onTap!(context)),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(
          ThumbnailListItem.defaultLeadingRadius,
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.strokeDark),
            borderRadius: BorderRadius.circular(
              ThumbnailListItem.defaultLeadingRadius,
            ),
          ),
          child: Center(
            child: Image.asset(
              "assets/new_album_icon.png",
              width: 20,
              height: 20,
            ),
          ),
        ),
      ),
      title: Text(
        AppLocalizations.of(context).createAlbum,
        style: TextStyles.body.copyWith(color: colors.textLight),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
