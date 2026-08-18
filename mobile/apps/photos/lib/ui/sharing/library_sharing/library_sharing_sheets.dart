import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/collections/album/list_item.dart';
import 'package:photos/ui/components/thumbnail_list_item.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_role_badge.dart';

typedef LibrarySharingAlbumThumbnailBuilder =
    Widget Function(BuildContext context, Collection album);

Future<CollectionParticipantRole?> showEnableLibrarySharingSheet({
  required BuildContext context,
  required String recipientLabel,
}) {
  var selectedRole = CollectionParticipantRole.viewer;
  return showBottomSheetComponent<CollectionParticipantRole>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = context.componentColors;
        return BottomSheetComponent(
          title: context.strings.librarySharingEnableTitle,
          borderSide: BorderSide(color: colors.strokeDark),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.strings.librarySharingEnableDescription(
                  recipient: recipientLabel,
                ),
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                context.strings.librarySharingHiddenAlbumsDescription,
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
                    onSelected: (role) => setState(() => selectedRole = role),
                    child: MenuComponent(
                      title: context.strings.librarySharingRole,
                      trailing: LibrarySharingRoleSelector(role: selectedRole),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ButtonComponent(
              label: context.strings.enable,
              density: ButtonComponentDensity.compact,
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(sheetContext).pop(selectedRole),
            ),
          ],
        );
      },
    ),
  );
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
              title: context.strings.librarySharingRoles,
              showCloseButton: !controller.isMutating,
              borderSide: BorderSide(color: colors.strokeDark),
              content: _LibrarySharingRoleList(
                controller: controller,
                thumbnailBuilder: albumThumbnailBuilder,
              ),
              actions: [
                ButtonComponent(
                  label: context.strings.librarySharingUpdateRoles,
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
            final canEditRole = album.type != CollectionType.uncategorized;
            final roleSelector = LibrarySharingRoleSelector(
              role: role,
              showChevron: canEditRole,
            );
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
              trailing: canEditRole
                  ? IgnorePointer(
                      ignoring: controller.isMutating,
                      child: EntePopupMenuButton<CollectionParticipantRole>(
                        optionsBuilder: () => librarySharingRoleOptions(
                          context,
                          activeRole: role,
                        ),
                        onSelected: (role) =>
                            controller.setRoleForAlbum(album.id, role),
                        child: roleSelector,
                      ),
                    )
                  : roleSelector,
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
            title: sheetContext.strings.librarySharingStopSharingTitle(
              count: count,
            ),
            message: sheetContext.strings.librarySharingStopSharingDescription(
              count: count,
            ),
            illustration: Image.asset('assets/warning-red.png'),
            borderSide: BorderSide(color: colors.strokeDark),
            actions: [
              ButtonComponent(
                label: sheetContext.strings.librarySharingStopSharing,
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

Future<bool> showPreviouslyUnsharedAlbums({
  required BuildContext context,
  required int count,
}) async {
  return await showBottomSheetComponent<bool>(
        context: context,
        builder: (sheetContext) => BottomSheetComponent(
          title: sheetContext.strings.librarySharingPreviouslyUnsharedTitle(
            count: count,
          ),
          message: sheetContext.strings
              .librarySharingPreviouslyUnsharedDescription(count: count),
          illustration: Image.asset('assets/warning-red.png'),
          borderSide: BorderSide(
            color: sheetContext.componentColors.strokeDark,
          ),
          actions: [
            ButtonComponent(
              label: sheetContext.strings.review,
              density: ButtonComponentDensity.compact,
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
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
    title: context.strings.librarySharingFailedTitle,
    message: count > 0
        ? context.strings.librarySharingFailedAlbumCount(count: count)
        : context.strings.librarySharingFailedDescription,
    actionLabel: context.strings.librarySharingRetryFailedAlbums,
    onActionTap: () async {
      Navigator.of(context).pop();
      await onRetry();
    },
  );
}
