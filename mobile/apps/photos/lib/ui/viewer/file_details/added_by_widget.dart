import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/services/collections_service.dart";
import "package:photos/ui/sharing/user_avatar_widget.dart";
import "package:photos/utils/avatar_util.dart";

class AddedByWidget extends StatelessWidget {
  final EnteFile file;

  const AddedByWidget(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!file.isUploaded) {
      return const SizedBox.shrink();
    }
    if (file.isOwner) {
      final uploaderName = file.uploaderName?.trim();
      if (uploaderName == null || uploaderName.isEmpty) {
        return const SizedBox.shrink();
      }
      final identity = AvatarIdentity.publicUploader(uploaderName);
      final colors = context.componentColors;
      return Padding(
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        child: Row(
          children: [
            AvatarIdentityWidget(identity, AvatarType.medium),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                context.strings.addedBy(emailOrName: identity.label),
                style: TextStyles.mini.copyWith(color: colors.textLighter),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      if (file.ownerID == null) {
        return const SizedBox.shrink();
      }
      final fileOwner = CollectionsService.instance.resolveUserIdentity(
        file.ownerID!,
        file.collectionID,
      );
      final identity = getUserAvatarIdentity(fileOwner);
      final colors = context.componentColors;
      return Padding(
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        child: Row(
          children: [
            UserAvatarWidget(fileOwner, type: AvatarType.medium),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                context.strings.addedBy(emailOrName: identity.label),
                style: TextStyles.mini.copyWith(color: colors.textLighter),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
  }
}
