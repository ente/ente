import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/pause_video_event.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";

class AlbumsItemWidget extends StatefulWidget {
  final EnteFile file;
  final int currentUserID;
  const AlbumsItemWidget(this.file, this.currentUserID, {super.key});

  @override
  State<AlbumsItemWidget> createState() => _AlbumsItemWidgetState();
}

class _AlbumsItemWidgetState extends State<AlbumsItemWidget> {
  @override
  Widget build(BuildContext context) {
    final Future<List<Widget>> chipsFuture;
    if (widget.file.uploadedFileID != null) {
      chipsFuture = _collectionsListOfFile(
        context,
        FilesDB.instance.getAllCollectionIDsOfFile(widget.file.uploadedFileID!),
        widget.currentUserID,
      );
    } else {
      chipsFuture = _deviceFoldersListOfFile(
        Future.sync(() => {widget.file.deviceFolder ?? ''}),
      );
    }

    return Column(
      key: const ValueKey("Albums"),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.strings.albums, style: TextStyles.h2),
        const SizedBox(height: Spacing.lg),
        FutureBuilder<List<Widget>>(
          future: chipsFuture,
          builder: (context, snapshot) {
            final chips = snapshot.data ?? const <Widget>[];
            return Wrap(
              spacing: widget.file.uploadedFileID == null
                  ? Spacing.sm
                  : Spacing.xs,
              runSpacing: widget.file.uploadedFileID == null ? Spacing.sm : 0,
              children: chips,
            );
          },
        ),
      ],
    );
  }

  Future<List<Widget>> _deviceFoldersListOfFile(
    Future<Set<String>> allDeviceFoldersOfFile,
  ) async {
    try {
      final chips = <Widget>[];
      final List<String> deviceFolders = (await allDeviceFoldersOfFile)
          .toList();
      for (var deviceFolder in deviceFolders) {
        chips.add(FilterChipComponent(label: deviceFolder, onChanged: (_) {}));
      }
      return chips;
    } catch (e, s) {
      Logger(
        "AlbumsItemWidget",
      ).info("Failed to build owned album chips", e, s);
      return [];
    }
  }

  Future<List<Widget>> _collectionsListOfFile(
    BuildContext context,
    Future<Set<int>> allCollectionIDsOfFile,
    int currentUserID,
  ) async {
    try {
      final colors = context.componentColors;
      final chips = <Widget>[];
      final Set<int> collectionIDs = await allCollectionIDsOfFile;
      if (!context.mounted) return const [];
      for (var collectionID in collectionIDs) {
        final c = CollectionsService.instance.getCollectionByID(collectionID)!;
        chips.add(
          _AlbumChip(
            label: c.isHidden() ? context.strings.hidden : c.displayName,
            onTap: () {
              if (c.isHidden()) return;
              Bus.instance.fire(PauseVideoEvent());
              routeToPage(
                context,
                CollectionPage(
                  CollectionWithThumbnail(c, null),
                  fileToJumpTo: widget.file,
                ),
              );
            },
            onRemove: _canRemoveFrom(c)
                ? () => _removeFromCollection(context, c)
                : null,
          ),
        );
      }
      chips.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Spacing.sm),
          child: IconButtonComponent(
            size: FilterChipComponent.minHeight,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedPlusSign,
              size: IconSizes.small,
              color: colors.textBase,
            ),
            variant: IconButtonComponentVariant.circular,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              final selectedFiles = SelectedFiles();
              selectedFiles.files.add(widget.file);
              await showCollectionActionSheet(
                context,
                selectedFiles: selectedFiles,
                actionType: CollectionActionType.addFiles,
              );
              if (mounted) setState(() {});
            },
          ),
        ),
      );
      return chips;
    } catch (e, s) {
      Logger(
        "AlbumsItemWidget",
      ).info("Failed to build shared album chips", e, s);
      return [];
    }
  }

  bool _canRemoveFrom(Collection collection) {
    if (collection.type == CollectionType.uncategorized ||
        collection.type == CollectionType.favorites ||
        collection.isQuickLinkCollection() ||
        collection.isDefaultHidden()) {
      return false;
    }
    return widget.file.ownerID == widget.currentUserID ||
        CollectionsService.instance.canRemoveFilesFromAllParticipants(
          collection,
        );
  }

  Future<void> _removeFromCollection(
    BuildContext context,
    Collection collection,
  ) async {
    final selectedFiles = SelectedFiles();
    selectedFiles.files.add(widget.file);
    final collectionActions = CollectionActions(CollectionsService.instance);
    final removingOthersFile =
        widget.file.ownerID != widget.currentUserID &&
        CollectionsService.instance.canRemoveFilesFromAllParticipants(
          collection,
        );
    await collectionActions.showRemoveFromCollectionSheetV2(
      context,
      collection,
      selectedFiles,
      removingOthersFile,
      isHidden: collection.isHidden(),
      body: context.strings.itemWillBeRemovedFromThisAlbum,
    );
    if (mounted) setState(() {});
  }
}

class _AlbumChip extends StatelessWidget {
  const _AlbumChip({required this.label, required this.onTap, this.onRemove});

  final String label;
  final VoidCallback onTap;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final chip = FilterChipComponent(label: label, onChanged: (_) => onTap());
    if (onRemove == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(
          top: Spacing.sm,
          end: Spacing.sm,
        ),
        child: chip,
      );
    }

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            top: Spacing.sm,
            end: Spacing.sm,
          ),
          child: chip,
        ),
        PositionedDirectional(
          top: Spacing.xs / 2,
          end: Spacing.xs / 2,
          child: _RemoveAlbumButton(onTap: onRemove!),
        ),
      ],
    );
  }
}

class _RemoveAlbumButton extends StatelessWidget {
  const _RemoveAlbumButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Tooltip(
      message: context.strings.removeFromAlbum,
      child: Semantics(
        button: true,
        label: context.strings.removeFromAlbum,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.fillBase,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: 10,
                        color: colors.textReverse,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
