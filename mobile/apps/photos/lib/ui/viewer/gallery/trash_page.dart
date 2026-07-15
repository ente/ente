import 'dart:io' show Platform;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/trash_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_trash_page_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/services/media_store_service.dart';
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
      asyncLoader: (_, _, {limit, asc}) async {
        final fileLists = await Future.wait([
          TrashDB.instance.getTrashedFiles().then((result) => result.files),
          _getSystemTrashFiles(),
        ]);
        final files = fileLists.expand((files) => files).toList();
        files.sort((first, second) {
          final firstTime = first.creationTime ?? 0;
          final secondTime = second.creationTime ?? 0;
          return asc ?? false
              ? firstTime.compareTo(secondTime)
              : secondTime.compareTo(firstTime);
        });
        return FileLoadResult(files, false);
      },
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

Future<List<EnteFile>> _getSystemTrashFiles() async {
  if (!Platform.isAndroid) {
    return const [];
  }
  try {
    return await MediaStoreService.getTrashItems();
  } on PlatformException catch (error) {
    if (error.code == "unsupported_android_version") {
      return const [];
    }
    rethrow;
  }
}
