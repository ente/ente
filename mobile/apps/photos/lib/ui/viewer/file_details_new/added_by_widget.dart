import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/utils/avatar_util.dart";

class AddedByWidgetNew extends StatelessWidget {
  const AddedByWidgetNew(this.file, {super.key});

  final EnteFile file;

  @override
  Widget build(BuildContext context) {
    if (!file.isUploaded) return const SizedBox.shrink();
    late final User user;
    late final AvatarIdentity identity;
    if (file.isOwner) {
      final uploaderName = file.uploaderName?.trim();
      if (uploaderName == null || uploaderName.isEmpty) {
        return const SizedBox.shrink();
      }
      identity = AvatarIdentity.publicUploader(label: uploaderName);
      user = User(
        email: normalizeAvatarEmail(uploaderName) ?? "",
        name: uploaderName,
      );
    } else {
      if (file.ownerID == null) return const SizedBox.shrink();
      user = CollectionsService.instance.getFileOwner(
        file.ownerID!,
        file.collectionID,
      );
      identity = getUserAvatarIdentity(user);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Row(
        children: [
          UserAvatarWidget(
            user,
            type: AvatarType.medium,
            fallbackIdentity: identity,
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              AppLocalizations.of(context).addedBy(emailOrName: identity.label),
              style: TextStyles.mini.copyWith(
                color: context.componentColors.textLighter,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
