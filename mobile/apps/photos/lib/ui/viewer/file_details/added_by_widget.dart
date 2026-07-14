import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/services/collections_service.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";

class AddedByWidget extends StatelessWidget {
  final EnteFile file;

  const AddedByWidget(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!file.isUploaded) {
      return const SizedBox.shrink();
    }
    late final String addedBy;
    if (file.isOwner) {
      final uploaderName = file.uploaderName?.trim();
      if (uploaderName == null || uploaderName.isEmpty) {
        return const SizedBox.shrink();
      }
      addedBy = uploaderName;
    } else {
      if (file.ownerID == null) {
        return const SizedBox.shrink();
      }
      final fileOwner = CollectionsService.instance.getFileOwner(
        file.ownerID!,
        file.collectionID,
      );
      addedBy = resolveDisplayName(fileOwner);
    }
    if (addedBy.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.componentColors;
    final initials = addedBy.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Row(
        children: [
          AvatarComponent.seeded(
            initials: initials,
            seed: addedBy.hashCode,
            size: AvatarComponentSize.defaultSize,
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              AppLocalizations.of(context).addedBy(emailOrName: addedBy),
              style: TextStyles.mini.copyWith(color: colors.textLighter),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
