import "dart:io";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/trash_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/force_reload_trash_page_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/native_service.dart";
import "package:photos/ui/components/empty_state_component.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  bool _isOnEnteTrash = true;
  final _selectedFiles = SelectedFiles();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final header = (isLocalGalleryMode || !Platform.isAndroid)
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                TagChipComponent(
                  label: l10n.ente,
                  state: _isOnEnteTrash ? .selected : .unselected,
                  onTap: () {
                    setState(() {
                      _isOnEnteTrash = true;
                    });
                  },
                ),
                TagChipComponent(
                  label: l10n.onDevice,
                  state: !_isOnEnteTrash ? .selected : .unselected,
                  onTap: () {
                    setState(() {
                      _isOnEnteTrash = false;
                    });
                  },
                ),
              ],
            ),
          );
    final appBarBottom = header == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(
              2 * Spacing.sm + TagChipComponent.preferredHeight(context),
            ),
            child: header,
          );
    final gallery = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Gallery(
        key: ValueKey(_isOnEnteTrash ? 'ente_trash_page' : 'device_trash_page'),
        enableFileGrouping: false,
        appBar: GalleryAppBarWidget.sliverConfig(
          GalleryType.trash,
          l10n.trash,
          _selectedFiles,
          subtitle:
              l10n.itemsShowTheNumberOfDaysRemainingBeforePermanentDeletion,
          bottom: appBarBottom,
        ),
        asyncLoader: _asyncLoader,
        reloadEvent: Bus.instance.on<FilesUpdatedEvent>().where(
          (event) =>
              event.updatedFiles.firstWhereOrNull(
                (element) => element.uploadedFileID != null,
              ) !=
              null,
        ),
        forceReloadEvents: [Bus.instance.on<ForceReloadTrashPageEvent>()],
        tagPrefix: "trash_page",
        selectedFiles: _selectedFiles,
        initialFiles: null,
        emptyState: EmptyStateComponent(
          assetPath: "assets/empty_state_trash.png",
          title: l10n.deletedItemsStayHereForThirtyDays,
        ),
      ),
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: SelectionState(
            selectedFiles: _selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                gallery,
                FileSelectionOverlayBar(GalleryType.trash, _selectedFiles),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<FileLoadResult> _asyncLoader(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) async {
    if (!Platform.isAndroid || (!isLocalGalleryMode && _isOnEnteTrash)) {
      return await TrashDB.instance.getTrashedFiles(
        creationStartTime,
        creationEndTime,
        limit: limit,
        asc: asc,
      );
    }
    final deviceTrash = await NativeService.getTrash();
    final deviceTrashAssets = await Future.wait(
      deviceTrash.map((t) => AssetEntity.fromId(t.localID.toString())),
    );
    final List<EnteFile> files = [];
    for (var i = 0; i < deviceTrash.length; i++) {
      final trash = deviceTrash[i];
      final asset = deviceTrashAssets[i];
      if (asset == null) continue;
      files.add(
        TrashFile.fromEnteFile(
          fileFromAsset(trash.deviceFolder, asset),
          createdAt: trash.deleteBy - 30 * 86400,
          updateAt: trash.deleteBy - 30 * 86400,
          deleteBy: trash.deleteBy,
          isSystemOnly: true,
          systemTrashID: trash.localID,
        ),
      );
    }
    return FileLoadResult(files, false);
  }
}
