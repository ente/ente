import "dart:io";

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/trash_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_trash_page_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/trash_file.dart";
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/module/metadata/local_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/native_service.dart";
import "package:photos/ui/components/empty_state_component.dart";
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart';
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class TrashPage extends StatelessWidget {
  final _selectedFiles = SelectedFiles();
  TrashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      GalleryType.trash,
      AppLocalizations.of(context).trash,
      _selectedFiles,
      subtitle: AppLocalizations.of(
        context,
      ).itemsShowTheNumberOfDaysRemainingBeforePermanentDeletion,
    );

    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final remoteTrash = await TrashDB.instance.getTrashedFiles();
        if (flagService.internalUser && Platform.isAndroid) {
          var localTrash = [];
          try {
            localTrash = await NativeService.getTrash();
          } catch (e, s) {
            Logger("trash_page").warning("failed to get trash files: ", e, s);
          }
          // Merge remote+local trash entries
          for (final file in remoteTrash.files) {
            if (file is TrashFile && file.isTrashedOnDevice) {
              localTrash.removeWhere((item) => item.localID == file.localID);
            }
          }
          // Insert local only trash entries
          final localTrashAssets = (await Future.wait(
            localTrash.map((item) => AssetEntity.fromId(item.localID)),
          )).toList();
          for (var i = 0; i < localTrash.length; i++) {
            if (localTrashAssets[i] == null) continue;
            final file = TrashFile.fromEnteFile(
              fileFromAsset('Unknown Folder', localTrashAssets[i]!),
              createdAt: 0,
              updateAt: 0,
              deleteBy: localTrash[i].deleteBy,
              isTrashedOnDevice: true,
            );
            for (var j = 0; j <= remoteTrash.files.length; j++) {
              if (j == remoteTrash.files.length ||
                  (remoteTrash.files[j] is TrashFile &&
                      (remoteTrash.files[j] as TrashFile).deleteBy <
                          localTrash[i].deleteBy)) {
                remoteTrash.files.insert(j, file);
                break;
              }
            }
          }
        }
        return remoteTrash;
      },
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
        title: AppLocalizations.of(context).deletedItemsStayHereForThirtyDays,
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
}
