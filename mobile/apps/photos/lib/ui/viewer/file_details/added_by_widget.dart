import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/services/collections_service.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/utils/avatar_util.dart";

class AddedByWidget extends StatelessWidget {
  final EnteFile file;

  const AddedByWidget(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!file.isUploaded) {
      return const SizedBox.shrink();
    }
    late final AvatarIdentity identity;
    if (file.isOwner) {
      final uploaderName = file.uploaderName?.trim();
      if (uploaderName == null || uploaderName.isEmpty) {
        return const SizedBox.shrink();
      }
      identity = AvatarIdentity.publicUploader(label: uploaderName);
    } else {
      if (file.ownerID == null) {
        return const SizedBox.shrink();
      }
      final fileOwner = CollectionsService.instance.getFileOwner(
        file.ownerID!,
        file.collectionID,
      );
      identity = getUserAvatarIdentity(fileOwner);
    }
    final colors = context.componentColors;
    final avatar = AvatarComponent(
      initials: identity.initial,
      color: avatarComponentColorForAvatarIdentity(identity),
      size: AvatarComponentSize.defaultSize,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              AppLocalizations.of(context).addedBy(emailOrName: identity.label),
              style: TextStyles.mini.copyWith(color: colors.textLighter),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
