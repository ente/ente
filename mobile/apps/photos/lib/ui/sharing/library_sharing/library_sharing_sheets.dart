import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/collections/album/list_item.dart';
import 'package:photos/ui/components/thumbnail_list_item.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_role_badge.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_strings.dart';

typedef LibrarySharingAlbumThumbnailBuilder =
    Widget Function(BuildContext context, Collection album);

List<EntePopupMenuOption<CollectionParticipantRole>> librarySharingRoleOptions(
  BuildContext context, {
  CollectionParticipantRole? activeRole,
}) {
  return [
    for (final role in const [
      CollectionParticipantRole.viewer,
      CollectionParticipantRole.collaborator,
      CollectionParticipantRole.admin,
    ])
      EntePopupMenuOption(
        value: role,
        label: librarySharingRoleLabel(context, role),
        leadingWidget: HugeIcon(
          icon: librarySharingRoleIcon(role),
          size: IconSizes.small,
          strokeWidth: 1.6,
        ),
        isActive: role == activeRole,
        activeTrailingWidget: const HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          size: IconSizes.small,
        ),
      ),
  ];
}

Future<bool> showEnableLibrarySharingSheet({
  required BuildContext context,
  required String recipientLabel,
}) async {
  var selectedRole = CollectionParticipantRole.admin;
  return await showBottomSheetComponent<bool>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setState) {
            final colors = context.componentColors;
            return BottomSheetComponent(
              title: LibrarySharingStrings.enableLibrarySharing,
              borderSide: BorderSide(color: colors.strokeDark),
              useSafeArea: false,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    LibrarySharingStrings.enableLibrarySharingMessage(
                      recipientLabel,
                    ),
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    LibrarySharingStrings.hiddenAlbumsNotShared,
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                  const SizedBox(height: Spacing.lg),
                  MenuGroupComponent(
                    items: [
                      EntePopupMenuButton<CollectionParticipantRole>(
                        optionsBuilder: () => librarySharingRoleOptions(
                          context,
                          activeRole: selectedRole,
                        ),
                        onSelected: (role) =>
                            setState(() => selectedRole = role),
                        child: MenuComponent(
                          title: LibrarySharingStrings.role,
                          trailing: LibrarySharingRoleSelector(
                            role: selectedRole,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                ButtonComponent(
                  label: LibrarySharingStrings.enable,
                  density: ButtonComponentDensity.compact,
                  shouldSurfaceExecutionStates: false,
                  onTap: () => Navigator.of(sheetContext).pop(true),
                ),
              ],
            );
          },
        ),
      ) ??
      false;
}

Future<bool?> showLibrarySharingRolesSheet({
  required BuildContext context,
  required LibrarySharingController controller,
  LibrarySharingAlbumThumbnailBuilder? albumThumbnailBuilder,
}) {
  return showBottomSheetComponent<bool>(
    context: context,
    enableDrag: false,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (sheetContext, _) => PopScope(
        canPop: !controller.isMutating,
        child: Builder(
          builder: (context) {
            final colors = context.componentColors;
            return BottomSheetComponent(
              title: LibrarySharingStrings.roles,
              showCloseButton: !controller.isMutating,
              borderSide: BorderSide(color: colors.strokeDark),
              useSafeArea: false,
              content: _LibrarySharingRoleList(
                controller: controller,
                thumbnailBuilder: albumThumbnailBuilder,
              ),
              actions: [
                ButtonComponent(
                  label: LibrarySharingStrings.updateRoles,
                  density: ButtonComponentDensity.compact,
                  isDisabled: !controller.canApply,
                  onTap: () async {
                    final success = await controller.applySelection();
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop(success);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _LibrarySharingRoleList extends StatelessWidget {
  const _LibrarySharingRoleList({
    required this.controller,
    this.thumbnailBuilder,
  });

  final LibrarySharingController controller;
  final LibrarySharingAlbumThumbnailBuilder? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    final albums = controller.selectedAlbums;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: Scrollbar(
        child: ListView.separated(
          key: const ValueKey('library-sharing-role-list'),
          primary: false,
          shrinkWrap: true,
          itemCount: albums.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) {
            final album = albums[index];
            final role = controller.stagedRoleFor(album.id);
            return ThumbnailListItem(
              leading:
                  thumbnailBuilder?.call(context, album) ??
                  AlbumListItemCover(collection: album, borderRadius: Radii.sm),
              leadingSize: 36,
              title: Text(
                album.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.body.copyWith(
                  color: context.componentColors.textBase,
                ),
              ),
              trailing: IgnorePointer(
                ignoring: controller.isMutating,
                child: EntePopupMenuButton<CollectionParticipantRole>(
                  optionsBuilder: () =>
                      librarySharingRoleOptions(context, activeRole: role),
                  onSelected: (role) =>
                      controller.setRoleForAlbum(album.id, role),
                  child: LibrarySharingRoleSelector(role: role),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<bool> confirmStopLibrarySharing({
  required BuildContext context,
  required int count,
}) async {
  return await showBottomSheetComponent<bool>(
        context: context,
        builder: (sheetContext) {
          final colors = sheetContext.componentColors;
          return BottomSheetComponent(
            title: LibrarySharingStrings.stopSharingTitle(count),
            message: LibrarySharingStrings.stopSharingMessage(count),
            illustration: Image.asset('assets/warning-red.png'),
            borderSide: BorderSide(color: colors.strokeDark),
            useSafeArea: false,
            actions: [
              ButtonComponent(
                label: LibrarySharingStrings.stopSharing,
                variant: ButtonComponentVariant.critical,
                density: ButtonComponentDensity.compact,
                shouldSurfaceExecutionStates: false,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          );
        },
      ) ??
      false;
}

Future<void> showLibrarySharingFailure({
  required BuildContext context,
  required LibrarySharingController controller,
  required Future<void> Function() onRetry,
}) {
  final count = controller.failedCount;
  return showErrorBottomSheetComponent<void>(
    context: context,
    title: LibrarySharingStrings.sharingFailed,
    message: count > 0
        ? LibrarySharingStrings.failedAlbumCount(count)
        : LibrarySharingStrings.sharingFailedMessage,
    actionLabel: LibrarySharingStrings.retryFailed,
    onActionTap: () async {
      Navigator.of(context).pop();
      await onRetry();
    },
  );
}
