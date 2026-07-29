import "dart:io";

import 'package:collection/collection.dart'
    show IterableExtension, IterableNumberExtension;
import 'package:flutter/material.dart';
import "package:photo_manager/photo_manager.dart";
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/trash_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_trash_page_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/file_load_result.dart";
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
  final String tagPrefix;
  final GalleryType appBarType;
  final GalleryType overlayType;
  final _selectedFiles = SelectedFiles();
  TrashPage({
    this.tagPrefix = "trash_page",
    this.appBarType = GalleryType.trash,
    this.overlayType = GalleryType.trash,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      appBarType,
      AppLocalizations.of(context).trash,
      _selectedFiles,
      subtitle: AppLocalizations.of(
        context,
      ).itemsShowTheNumberOfDaysRemainingBeforePermanentDeletion,
    );

    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: _asyncLoader,
      reloadEvent: Bus.instance.on<FilesUpdatedEvent>().where(
        (event) =>
            event.updatedFiles.firstWhereOrNull(
              (element) => element.uploadedFileID != null,
            ) !=
            null,
      ),
      forceReloadEvents: [Bus.instance.on<ForceReloadTrashPageEvent>()],
      tagPrefix: tagPrefix,
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

Future<FileLoadResult> _asyncLoader(
  int creationStartTime,
  int creationEndTime, {
  int? limit,
  bool? asc,
}) async {
  assert(asc == false);
  final result = await TrashDB.instance.getTrashedFiles(
    creationStartTime,
    creationEndTime,
    limit: limit,
    asc: asc,
  );
  for (final file in result.files) {
    file.localID = null;
  }
  var generatedID =
      result.files.map((f) => f.generatedID).whereType<int>().minOrNull ?? 0;
  if (Platform.isAndroid && flagService.internalUser) {
    final systemTrash = await NativeService.getTrash();
    final systemTrashAssets = await Future.wait(
      systemTrash.map((t) => AssetEntity.fromId(t.localID.toString())),
    );
    for (var i = 0; i < systemTrash.length; i++) {
      if (systemTrashAssets[i] == null) continue;
      final enteFile = TrashFile.fromEnteFile(
        fileFromAsset(systemTrash[i].deviceFolder, systemTrashAssets[i]!),
        createdAt: systemTrash[i].deleteBy - 30 * 86400,
        updateAt: systemTrash[i].deleteBy - 30 * 86400,
        deleteBy: systemTrash[i].deleteBy,
        isSystemOnly: true,
        systemTrashID: systemTrash[i].localID,
      );
      generatedID--;
      enteFile.generatedID = generatedID as int;
      for (var j = 0; j <= result.files.length; j++) {
        if (j == result.files.length ||
            (result.files[j].creationTime ?? 0) <
                (enteFile.creationTime ?? 0)) {
          result.files.insert(j, enteFile);
          break;
        }
      }
    }
  }
  return result;
}
