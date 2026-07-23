import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/ignored_upload_reason.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/device/ignored_uploads.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class SkippedDeviceFolderPage extends StatefulWidget {
  final DeviceCollection deviceCollection;
  final bool shouldBackup;
  final Future<bool> Function(bool shouldBackup) onBackupChanged;

  const SkippedDeviceFolderPage(
    this.deviceCollection, {
    required this.shouldBackup,
    required this.onBackupChanged,
    super.key,
  });

  @override
  State<SkippedDeviceFolderPage> createState() =>
      _SkippedDeviceFolderPageState();
}

class _SkippedDeviceFolderPageState extends State<SkippedDeviceFolderPage> {
  final _logger = Logger("_SkippedDeviceFolderPageState");
  final _selectedFiles = SelectedFiles();
  final _filterReloadController = StreamController<FilesUpdatedEvent>();
  late final StreamSubscription<LocalPhotosUpdatedEvent> _localPhotosSub;
  late Future<List<EnteFile>> _filesInDeviceCollection;
  late Future<Set<IgnoredUploadReasonBucket>> _ignoredUploadBuckets;
  late bool _shouldBackup;
  IgnoredUploadReasonBucket? _selectedBucket;

  @override
  void initState() {
    super.initState();
    _shouldBackup = widget.shouldBackup;
    _refreshIgnoredState();
    _localPhotosSub = Bus.instance.on<LocalPhotosUpdatedEvent>().listen((_) {
      if (!mounted) {
        return;
      }
      setState(_refreshIgnoredState);
      unawaited(_syncSelectedBucket(popIfEmpty: true));
    });
    unawaited(_syncSelectedBucket(popIfEmpty: false));
  }

  Future<FileLoadResult> _loadFiles(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) async {
    final selectedBucket = _selectedBucket;
    if (selectedBucket == null) {
      return FileLoadResult(const [], false);
    }
    final files = await _refreshFilesInDeviceCollection();
    final idToReasonMap =
        await IgnoredFilesService.instance.idToIgnoreReasonMap;
    return FileLoadResult(
      files
          .where(
            (file) =>
                ignoredUploadReasonBucketForFile(idToReasonMap, file) ==
                selectedBucket,
          )
          .toList(),
      false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appBar = GalleryAppBarWidget.sliverConfig(
      GalleryType.localFolder,
      l10n.skippedFiles,
      _selectedFiles,
      deviceCollection: widget.deviceCollection,
      isDeviceFolderBackedUp: _shouldBackup,
      onDisableDeviceFolderBackup: () async {
        await _updateBackupStatus(false);
      },
    );
    final gallery = Gallery(
      key: ValueKey("skipped_device_folder:${widget.deviceCollection.id}"),
      appBar: appBar,
      asyncLoader: _loadFiles,
      forceReloadEvents: [_filterReloadController.stream],
      removalEventTypes: const {
        EventType.deletedFromDevice,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      tagPrefix: "skipped_device_folder:${widget.deviceCollection.name}",
      galleryType: GalleryType.localFolder,
      selectedFiles: _selectedFiles,
      header: SkippedFilesHeaderWidget(
        availableBuckets: _ignoredUploadBuckets,
        selectedBucket: _selectedBucket,
        onBucketChanged: _onBucketChanged,
        onResetIgnoredFiles: _resetFilesInSelectedReason,
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
                FileSelectionOverlayBar(
                  GalleryType.localFolder,
                  _selectedFiles,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onBucketChanged(IgnoredUploadReasonBucket bucket) {
    if (_selectedBucket == bucket) {
      return;
    }
    _selectedFiles.clearAll();
    setState(() {
      _selectedBucket = bucket;
    });
    _reloadSkippedFiles("ignoredUploadFilterChanged:${bucket.name}");
  }

  Future<void> _resetFilesInSelectedReason() async {
    final selectedBucket = _selectedBucket;
    if (selectedBucket == null) {
      return;
    }
    final files = await _ignoredFilesForBucket(selectedBucket);
    await IgnoredFilesService.instance.removeIgnoredMappings(files);
    if (!mounted) {
      return;
    }
    _selectedFiles.clearAll();
    setState(_refreshIgnoredState);
    await _syncSelectedBucket(popIfEmpty: true);
    unawaited(RemoteSyncService.instance.sync(silently: true));
  }

  Future<void> _updateBackupStatus(bool shouldBackup) async {
    final updated = await widget.onBackupChanged(shouldBackup);
    if (!mounted || !updated) {
      return;
    }
    setState(() {
      _shouldBackup = shouldBackup;
    });
    if (!shouldBackup) {
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _syncSelectedBucket({required bool popIfEmpty}) async {
    try {
      final buckets = await _ignoredUploadBuckets;
      if (!mounted) {
        return;
      }
      final visibleBuckets = visibleIgnoredUploadBuckets(buckets);
      if (visibleBuckets.isEmpty) {
        setState(() {
          _selectedBucket = null;
        });
        _reloadSkippedFiles("ignoredUploadBucketsEmpty");
        if (popIfEmpty) {
          await Navigator.of(context).maybePop();
        }
        return;
      }
      final currentBucket = _selectedBucket;
      final nextBucket =
          currentBucket != null && visibleBuckets.contains(currentBucket)
          ? currentBucket
          : visibleBuckets.first;
      if (nextBucket != _selectedBucket) {
        setState(() {
          _selectedBucket = nextBucket;
        });
      }
      _reloadSkippedFiles("ignoredUploadBucketsChanged");
    } catch (e, s) {
      _logger.severe("Could not refresh ignored upload buckets", e, s);
    }
  }

  Future<List<EnteFile>> _ignoredFilesForBucket(
    IgnoredUploadReasonBucket bucket,
  ) async {
    final files = await _filesInDeviceCollection;
    final idToReasonMap =
        await IgnoredFilesService.instance.idToIgnoreReasonMap;
    return files
        .where(
          (file) =>
              ignoredUploadReasonBucketForFile(idToReasonMap, file) == bucket,
        )
        .toList();
  }

  void _refreshIgnoredState() {
    _filesInDeviceCollection = _refreshFilesInDeviceCollection();
    _ignoredUploadBuckets = ignoredUploadReasonBuckets(
      _filesInDeviceCollection,
    );
  }

  Future<List<EnteFile>> _refreshFilesInDeviceCollection() {
    final files = filesInDeviceCollectionFor(widget.deviceCollection);
    _filesInDeviceCollection = files;
    return files;
  }

  void _reloadSkippedFiles(String source) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _filterReloadController.isClosed) {
        return;
      }
      _filterReloadController.add(FilesUpdatedEvent(const [], source: source));
    });
  }

  @override
  void dispose() {
    _localPhotosSub.cancel();
    _filterReloadController.close();
    super.dispose();
  }
}

class SkippedFilesHeaderWidget extends StatelessWidget {
  final Future<Set<IgnoredUploadReasonBucket>> availableBuckets;
  final IgnoredUploadReasonBucket? selectedBucket;
  final ValueChanged<IgnoredUploadReasonBucket> onBucketChanged;
  final Future<void> Function() onResetIgnoredFiles;

  const SkippedFilesHeaderWidget({
    required this.availableBuckets,
    required this.selectedBucket,
    required this.onBucketChanged,
    required this.onResetIgnoredFiles,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<IgnoredUploadReasonBucket>>(
      future: availableBuckets,
      builder: (context, snapshot) {
        final visibleBuckets = visibleIgnoredUploadBuckets(
          snapshot.data ?? <IgnoredUploadReasonBucket>{},
        );
        if (visibleBuckets.isEmpty) {
          return const SizedBox.shrink();
        }
        final effectiveSelectedBucket = selectedBucket ?? visibleBuckets.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final bucket in visibleBuckets)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TagChipComponent(
                          key: ValueKey("ignored_upload_filter_${bucket.name}"),
                          label: ignoredUploadReasonBucketLabel(
                            context,
                            bucket,
                          ),
                          state: effectiveSelectedBucket == bucket
                              ? TagChipComponentState.selected
                              : TagChipComponentState.unselected,
                          onTap: () => onBucketChanged(bucket),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ResetIgnoredFilesSection(
                onResetIgnoredFiles: onResetIgnoredFiles,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResetIgnoredFilesSection extends StatelessWidget {
  final Future<void> Function() onResetIgnoredFiles;

  const _ResetIgnoredFilesSection({required this.onResetIgnoredFiles});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).resetIgnoredFilesDescription,
          style: textTheme.smallMuted,
        ),
        const SizedBox(height: 12),
        ButtonComponent(
          variant: ButtonComponentVariant.secondary,
          label: AppLocalizations.of(context).resetIgnoredFiles,
          onTap: onResetIgnoredFiles,
        ),
      ],
    );
  }
}
