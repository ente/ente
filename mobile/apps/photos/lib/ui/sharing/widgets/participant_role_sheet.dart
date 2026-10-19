import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/sharing/share_components.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";

enum ParticipantRoleAction {
  viewer(CollectionParticipantRole.viewer),
  collaborator(CollectionParticipantRole.collaborator),
  admin(CollectionParticipantRole.admin),
  remove(null);

  const ParticipantRoleAction(this.role);

  final CollectionParticipantRole? role;
}

Future<ParticipantRoleAction?> showParticipantRoleSheet(
  BuildContext context, {
  required String email,
  required CollectionParticipantRole currentRole,
}) {
  return showBottomSheetComponent<ParticipantRoleAction>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.componentColors;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.95,
        ),
        child: BottomSheetComponent(
          title: sheetContext.strings.chooseAccess,
          content: Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                  const SizedBox(height: Spacing.xl),
                  ShareMenuGroup(
                    items: [
                      for (final action in ParticipantRoleAction.values)
                        if (action.role case final role?)
                          Semantics(
                            selected: currentRole == role,
                            child: ShareMenuItem(
                              title: shareableRoleLabel(sheetContext, role),
                              icon: albumSharingRoleIcon(role),
                              trailing: currentRole == role
                                  ? const CollectionSelectedBadge()
                                  : SizedBox.square(
                                      dimension: IconSizes.small,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colors.strokeDark,
                                          ),
                                        ),
                                      ),
                                    ),
                              onTap: () =>
                                  Navigator.of(sheetContext).pop(action),
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                  ShareMenuGroup(
                    items: [
                      ShareMenuItem(
                        title: sheetContext.strings.removeFromAlbum,
                        icon: HugeIcons.strokeRoundedDelete02,
                        isDestructive: true,
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(ParticipantRoleAction.remove),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
