import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/core/user_config.dart";
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_home_gallery_event.dart';
import "package:photos/events/hide_shared_items_from_home_gallery_event.dart";
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/services/filter/db_filters.dart";
import "package:photos/services/sync/sync_service.dart";
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import 'package:photos/ui/viewer/gallery/gallery.dart';
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class HomeGalleryWidget extends StatefulWidget {
  final Widget? header;
  final Widget? footer;
  final SelectedFiles selectedFiles;
  final GroupType? groupType;

  const HomeGalleryWidget({
    super.key,
    this.header,
    this.footer,
    this.groupType,
    required this.selectedFiles,
  });

  @override
  State<HomeGalleryWidget> createState() => _HomeGalleryWidgetState();
}

class _HomeGalleryWidgetState extends State<HomeGalleryWidget> {
  static const _maxFastAddFiles = 50;
  late final StreamSubscription<HideSharedItemsFromHomeGalleryEvent>
  _hideSharedFilesFromHomeSubscription;
  bool _shouldHideSharedItems = localSettings.hideSharedItemsFromHomeGallery;

  // Delay the gallery rebuild so the settings toggle stays smooth.
  final _hideSharedItemsToggleDebouncer = Debouncer(
    const Duration(milliseconds: 500),
  );

  DBFilterOptions get _filterOptions => DBFilterOptions(
    hideIgnoredForUpload: true,
    dedupeUploadID: true,
    ignoredCollectionIDs: CollectionsService.instance
        .archivedOrHiddenCollectionIds(),
    ignoreSavedFiles: true,
    ignoreSharedItems: _shouldHideSharedItems,
  );

  Future<List<EnteFile>?> _resolveNewLocalFiles(
    LocalPhotosAddedEvent event,
  ) async {
    final files = event.updatedFiles;
    final filterOptions = _filterOptions;
    if (files.any(
      (file) =>
          file.localID == null ||
          file.creationTime == null ||
          file.modificationTime == null,
    )) {
      return null;
    }

    var candidates = files;
    if (!isLocalGalleryMode) {
      if (files.length > _maxFastAddFiles ||
          !event.hasRecentNewLocalDiscovery) {
        return null;
      }
      if (!backupPreferenceService.hasSelectedAllFoldersForBackup) {
        final onlyNewSince = backupPreferenceService.onlyNewSinceEpoch;
        if (onlyNewSince != null) {
          candidates = candidates
              .where((file) => file.creationTime! >= onlyNewSince)
              .toList(growable: false);
        }
        final localIDs = candidates.map((file) => file.localID!).toSet();
        final selectedLocalIDs = await FilesDB.instance
            .getLocalIDsInBackupFolders(
              localIDs,
              filterOptions.ignoredCollectionIDs ?? {},
            );
        candidates = candidates
            .where((file) => selectedLocalIDs.contains(file.localID))
            .toList(growable: false);
      }
    }
    return applyDBFilters(candidates, filterOptions);
  }

  @override
  void initState() {
    super.initState();
    _hideSharedFilesFromHomeSubscription = Bus.instance
        .on<HideSharedItemsFromHomeGalleryEvent>()
        .listen((event) {
          localSettings.setHideSharedItemsFromHomeGallery(event.shouldHide);
          _hideSharedItemsToggleDebouncer.run(() async {
            setState(() {
              _shouldHideSharedItems = event.shouldHide;
            });
          });
        });
  }

  @override
  void dispose() {
    super.dispose();
    _hideSharedFilesFromHomeSubscription.cancel();
    _hideSharedItemsToggleDebouncer.cancelDebounceTimer();
  }

  @override
  Widget build(BuildContext context) {
    final largeBackupSession = SyncService.instance.largeBackupSessionTracker;
    final gallery = Gallery(
      key: ValueKey(_shouldHideSharedItems),
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final ownerID = Configuration.instance.getUserIDV2();
        final hasSelectedAllForBackup =
            backupPreferenceService.hasSelectedAllFoldersForBackup ||
            isLocalGalleryMode;
        FileLoadResult result;
        final filterOptions = _filterOptions;
        if (hasSelectedAllForBackup) {
          result = await FilesDB.instance.getAllLocalAndUploadedFiles(
            creationStartTime,
            creationEndTime,
            ownerID,
            limit: limit,
            asc: asc,
            filterOptions: filterOptions,
          );
        } else {
          result = await FilesDB.instance.getAllPendingOrUploadedFiles(
            creationStartTime,
            creationEndTime,
            ownerID,
            limit: limit,
            asc: asc,
            filterOptions: filterOptions,
          );
        }

        return result;
      },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>().where(
        (_) => !largeBackupSession.isStandbyScreenActive,
      ),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.archived,
        EventType.hide,
      },
      forceReloadEvents: [
        Bus.instance.on<ForceReloadHomeGalleryEvent>().where(
          (_) => !largeBackupSession.isStandbyScreenActive,
        ),
      ],
      tagPrefix: "home_gallery",
      selectedFiles: widget.selectedFiles,
      header: widget.header,
      footer: widget.footer,
      reloadDebounceTime: const Duration(seconds: 2),
      reloadDebounceExecutionInterval: const Duration(seconds: 5),
      priorityReloadDebounceTime: const Duration(milliseconds: 200),
      newLocalFilesResolver: _resolveNewLocalFiles,
      galleryType: GalleryType.homepage,
      groupType: widget.groupType,
      showGallerySettingsCTA: true,
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: SelectionState(
          selectedFiles: widget.selectedFiles,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              gallery,
              FileSelectionOverlayBar(
                GalleryType.homepage,
                widget.selectedFiles,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
