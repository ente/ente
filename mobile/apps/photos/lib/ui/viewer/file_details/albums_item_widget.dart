import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
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
  Future<List<Widget>>? _chipsFuture;

  @override
  Widget build(BuildContext context) {
    _chipsFuture ??= _buildChips(context);
    return Column(
      key: const ValueKey("Albums"),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(AppLocalizations.of(context).albums, style: TextStyles.h2),
        const SizedBox(height: Spacing.lg),
        FutureBuilder<List<Widget>>(
          future: _chipsFuture,
          builder: (context, snapshot) {
            final chips = snapshot.data ?? const <Widget>[];
            return Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: chips,
            );
          },
        ),
      ],
    );
  }

  Future<List<Widget>> _buildChips(BuildContext context) {
    final file = widget.file;
    if (file.uploadedFileID != null) {
      return _collectionsListOfFile(
        context,
        FilesDB.instance.getAllCollectionIDsOfFile(file.uploadedFileID!),
        widget.currentUserID,
      );
    }
    return _deviceFoldersListOfFile(
      context,
      Future.sync(() => {file.deviceFolder ?? ''}),
    );
  }

  Future<List<Widget>> _deviceFoldersListOfFile(
    BuildContext context,
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
          FilterChipComponent(
            label: c.isHidden()
                ? AppLocalizations.of(context).hidden
                : c.displayName,
            onChanged: (_) {
              if (c.isHidden()) {
                return;
              }
              Bus.instance.fire(PauseVideoEvent());
              routeToPage(
                context,
                CollectionPage(
                  CollectionWithThumbnail(c, null),
                  fileToJumpTo: widget.file,
                ),
              );
            },
          ),
        );
      }
      chips.add(
        IconButtonComponent(
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSign,
            size: IconSizes.small,
            color: colors.textBase,
          ),
          variant: IconButtonComponentVariant.circular,
          shouldSurfaceExecutionStates: false,
          onTap: () {
            final selectedFiles = SelectedFiles();
            selectedFiles.files.add(widget.file);
            showCollectionActionSheet(
              context,
              selectedFiles: selectedFiles,
              actionType: CollectionActionType.addFiles,
            );
          },
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
}
