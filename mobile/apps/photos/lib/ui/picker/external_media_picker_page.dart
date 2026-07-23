import "dart:async";

import "package:flutter/material.dart";
import "package:media_extension/media_extension.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/backup_folders_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/download/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/theme/effects.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class ExternalMediaPickerPage extends StatefulWidget {
  final MediaType? requestedType;
  final bool allowMultiple;

  const ExternalMediaPickerPage({
    this.requestedType,
    this.allowMultiple = false,
    super.key,
  });

  @override
  State<ExternalMediaPickerPage> createState() =>
      _ExternalMediaPickerPageState();
}

class _ExternalMediaPickerPageState extends State<ExternalMediaPickerPage> {
  final _selectedFiles = SelectedFiles();
  bool _isCompleting = false;

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  Future<FileLoadResult> _loadFiles(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) async {
    if (!isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount()) {
      return FileLoadResult(<EnteFile>[], false);
    }
    final ownerID = Configuration.instance.getUserIDV2();
    final hasSelectedAllForBackup =
        backupPreferenceService.hasSelectedAllFoldersForBackup ||
        isLocalGalleryMode;
    final collectionsToHide = CollectionsService.instance
        .archivedOrHiddenCollectionIds();
    final filterOptions = DBFilterOptions(
      hideIgnoredForUpload: true,
      dedupeUploadID: true,
      ignoredCollectionIDs: collectionsToHide,
      ignoreSavedFiles: true,
      ignoreSharedItems: localSettings.hideSharedItemsFromHomeGallery,
    );

    final result = hasSelectedAllForBackup
        ? await FilesDB.instance.getAllLocalAndUploadedFiles(
            creationStartTime,
            creationEndTime,
            ownerID,
            limit: limit,
            asc: asc,
            filterOptions: filterOptions,
          )
        : await FilesDB.instance.getAllPendingOrUploadedFiles(
            creationStartTime,
            creationEndTime,
            ownerID,
            limit: limit,
            asc: asc,
            filterOptions: filterOptions,
          );

    if (widget.requestedType == null) {
      return result;
    }

    return FileLoadResult(
      result.files.where(_matchesRequestedType).toList(),
      result.hasMore,
    );
  }

  bool _matchesRequestedType(EnteFile file) {
    switch (widget.requestedType) {
      case MediaType.image:
        return file.fileType == FileType.image ||
            file.fileType == FileType.livePhoto;
      case MediaType.video:
        return file.fileType == FileType.video;
      case null:
        return true;
    }
  }

  Future<void> _completeSelection() async {
    if (_isCompleting || _selectedFiles.files.isEmpty) {
      return;
    }
    setState(() {
      _isCompleting = true;
    });
    final selectedFiles = _selectedFiles.files.toList();
    final uris = <String>[];
    for (final file in selectedFiles) {
      final ioFile = await getFile(file);
      if (ioFile != null) {
        uris.add(ioFile.uri.toString());
      }
    }

    if (!mounted) {
      return;
    }
    if (uris.isEmpty) {
      showShortToast(context, AppLocalizations.of(context).somethingWentWrong);
      setState(() {
        _isCompleting = false;
      });
      return;
    }

    if (uris.length == 1) {
      await MediaExtension().setResult(uris.first);
    } else {
      await MediaExtension().setResults(uris);
    }
  }

  Future<void> _handleBack() async {
    if (_isCompleting) {
      return;
    }
    if (_selectedFiles.files.isNotEmpty) {
      _selectedFiles.clearAll();
      return;
    }
    await MediaExtension().cancelResult();
  }

  @override
  Widget build(BuildContext context) {
    final gallery = Gallery(
      asyncLoader: _loadFiles,
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.archived,
        EventType.hide,
      },
      forceReloadEvents: [
        Bus.instance.on<BackupFoldersUpdatedEvent>(),
        Bus.instance.on<ForceReloadHomeGalleryEvent>(),
      ],
      tagPrefix: "external_media_picker",
      selectedFiles: _selectedFiles,
      footer: const SizedBox(height: 156),
      inSelectionMode: true,
      limitSelectionToOne: !widget.allowMultiple,
      showSelectAll: false,
      galleryType: GalleryType.homepage,
      reloadDebounceTime: const Duration(seconds: 2),
      reloadDebounceExecutionInterval: const Duration(seconds: 5),
      priorityReloadDebounceTime: const Duration(milliseconds: 200),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_handleBack());
      },
      child: GalleryBoundariesProvider(
        child: GalleryFilesState(
          child: SelectionState(
            selectedFiles: _selectedFiles,
            child: Scaffold(
              appBar: AppBar(
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => unawaited(MediaExtension().cancelResult()),
                ),
                title: AnimatedBuilder(
                  animation: _selectedFiles,
                  builder: (context, _) {
                    final selectedCount = _selectedFiles.files.length;
                    return Text(
                      selectedCount == 0
                          ? AppLocalizations.of(context).selectItemsToAdd
                          : AppLocalizations.of(
                              context,
                            ).selectedPhotos(count: selectedCount),
                      style: getEnteTextTheme(context).largeBold,
                    );
                  },
                ),
              ),
              body: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  gallery,
                  _PickerActionBar(
                    selectedFiles: _selectedFiles,
                    isCompleting: _isCompleting,
                    onCancel: () => _selectedFiles.clearAll(),
                    onDone: _completeSelection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerActionBar extends StatelessWidget {
  final SelectedFiles selectedFiles;
  final bool isCompleting;
  final VoidCallback onCancel;
  final Future<void> Function() onDone;

  const _PickerActionBar({
    required this.selectedFiles,
    required this.isCompleting,
    required this.onCancel,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: selectedFiles,
      builder: (context, _) {
        final selectedCount = selectedFiles.files.length;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selectedCount == 0
              ? const SizedBox.shrink()
              : Padding(
                  key: const ValueKey("picker-action-bar"),
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    decoration: BoxDecoration(boxShadow: shadowFloatFaintLight),
                    child: _PickerBottomActionBar(
                      selectedCount: selectedCount,
                      isCompleting: isCompleting,
                      onCancel: onCancel,
                      onDone: onDone,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _PickerBottomActionBar extends StatelessWidget {
  final int selectedCount;
  final bool isCompleting;
  final VoidCallback onCancel;
  final Future<void> Function() onDone;

  const _PickerBottomActionBar({
    required this.selectedCount,
    required this.isCompleting,
    required this.onCancel,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final widthOfScreen = MediaQuery.sizeOf(context).width;
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final leftRightPadding = widthOfScreen > restrictedMaxWidth
        ? (widthOfScreen - restrictedMaxWidth) / 2
        : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        leftRightPadding + 16,
        16,
        leftRightPadding + 16,
        bottomPadding + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).selectedPhotos(count: selectedCount),
            style: textTheme.miniMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ButtonWidgetV2(
                  buttonType: ButtonTypeV2.secondary,
                  buttonSize: ButtonSizeV2.large,
                  labelText: AppLocalizations.of(context).cancel,
                  isDisabled: isCompleting,
                  shouldSurfaceExecutionStates: false,
                  onTap: isCompleting
                      ? null
                      : () async {
                          onCancel();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ButtonWidgetV2(
                  buttonType: ButtonTypeV2.primary,
                  buttonSize: ButtonSizeV2.large,
                  labelText: AppLocalizations.of(context).done,
                  isDisabled: isCompleting,
                  onTap: isCompleting ? null : onDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
