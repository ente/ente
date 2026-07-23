import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import 'package:photos/events/collection_updated_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/services/collections_service.dart';

class DeleteEmptyAlbums extends StatefulWidget {
  final Future<void> Function()? onDeleted;
  final EdgeInsetsGeometry padding;

  const DeleteEmptyAlbums({
    super.key,
    this.onDeleted,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  State<DeleteEmptyAlbums> createState() => _DeleteEmptyAlbumsState();
}

class _DeleteEmptyAlbumsState extends State<DeleteEmptyAlbums> {
  final ValueNotifier<String> _deleteProgress = ValueNotifier("");
  bool _isCancelled = false;

  @override
  void dispose() {
    _deleteProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _confirmAndDeleteEmptyAlbums,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: widget.padding,
          child: Text(
            AppLocalizations.of(context).deleteEmptyAlbums,
            style: TextStyles.body.copyWith(
              color: colors.textLight,
              decoration: TextDecoration.underline,
              decorationColor: colors.textLight,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteEmptyAlbums() async {
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent<void>(
      context: context,
      isDismissible: true,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.deleteEmptyAlbumsWithQuestionMark,
        message: l10n.deleteAlbumsDialogBody,
        illustration: Image.asset("assets/warning-grey.png"),
        closeTooltip: l10n.close,
        onClose: () {
          _isCancelled = true;
        },
        actions: [
          ButtonComponent(
            label: l10n.yes,
            variant: ButtonComponentVariant.critical,
            shouldSurfaceExecutionStates: true,
            progressStatus: _deleteProgress,
            onTap: () async {
              _isCancelled = false;
              _deleteProgress.value = "";
              await _deleteEmptyAlbums();
              Bus.instance.fire(
                CollectionUpdatedEvent(0, <EnteFile>[], "empty_albums_deleted"),
              );
              CollectionsService.instance.sync().ignore();
              _isCancelled = false;
              await widget.onDeleted?.call();
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmptyAlbums() async {
    final collections = CollectionsService.instance.getCollectionsForUI();
    final idToFileTimeStamp = await FilesDB.instance
        .getCollectionIDToMaxCreationTime();

    // remove collections which are not empty or can't be deleted
    collections.removeWhere(
      (c) => !c.type.canDelete || idToFileTimeStamp.containsKey(c.id),
    );
    int failedCount = 0;
    final int totalCount = collections.length;
    final int totalDigits = totalCount.toString().length;

    for (int i = 0; i < totalCount; i++) {
      if (mounted && !_isCancelled) {
        try {
          await CollectionsService.instance.trashEmptyCollection(
            collections[i],
            isBulkDelete: true,
          );
        } catch (_) {
          failedCount++;
        }
        if (!mounted || _isCancelled) {
          return;
        }
        final int current = i + 1;
        final String currentlyDeleting = current.toString().padLeft(
          totalDigits,
          '0',
        );

        _deleteProgress.value = AppLocalizations.of(context).deleteProgress(
          currentlyDeleting: currentlyDeleting,
          totalCount: totalCount,
        );
      }
    }
    if (failedCount > 0) {
      debugPrint("Delete ops failed for $failedCount collections");
    }
  }
}
