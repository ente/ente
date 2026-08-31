import "dart:async";
import "dart:io";
import "package:collection/collection.dart";

import "package:ente_icons/ente_icons.dart";
import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:hugeicons/hugeicons.dart";
import "package:local_auth/local_auth.dart";
import "package:logging/logging.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photo_manager/photo_manager.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/device_files_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/backup_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/force_reload_trash_page_event.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/people_changed_event.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/device_collection.dart';
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/file/trash_file.dart";
import 'package:photos/models/files_split.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/ml/face/person.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/module/download/gallery.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/device_folder_confirmed_move_planner.dart';
import 'package:photos/services/device_folder_transfer_coordinator.dart';
import 'package:photos/services/hidden_service.dart';
import 'package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import 'package:photos/settings/local_settings.dart';
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/actions/collection/collection_file_actions.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/collections/collection_action_sheet.dart';
import 'package:photos/ui/collections/device/device_folder_action_sheet.dart';
import "package:photos/ui/common/photo_library_add_permission.dart";
import 'package:photos/ui/components/action_sheet_widget.dart';
import "package:photos/ui/components/bottom_action_bar/selection_action_button_widget.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/tools/collage/collage_creator_page.dart";
import "package:photos/ui/viewer/actions/suggest_delete_sheet.dart";
import "package:photos/ui/viewer/date/edit_date_sheet.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/device/device_folder_page.dart";
import "package:photos/ui/viewer/location/update_location_data_widget.dart";
import "package:photos/ui/viewer/people/add_files_to_person_page.dart";
import 'package:photos/utils/delete_file_util.dart';
import "package:photos/utils/dialog_util.dart";
import 'package:photos/utils/magic_util.dart';
import "package:photos/utils/share_util.dart";

class FileSelectionActionsWidget extends StatefulWidget {
  final GalleryType type;
  final Collection? collection;
  final DeviceCollection? deviceCollection;
  final SelectedFiles selectedFiles;
  final PersonEntity? person;
  final String? clusterID;

  const FileSelectionActionsWidget(
    this.type,
    this.selectedFiles, {
    super.key,
    this.collection,
    this.person,
    this.clusterID,
    this.deviceCollection,
  });

  @override
  State<FileSelectionActionsWidget> createState() =>
      _FileSelectionActionsWidgetState();
}

class _FileSelectionActionsWidgetState
    extends State<FileSelectionActionsWidget> {
  static final _logger = Logger("FileSelectionActionsWidget");
  late int currentUserID;
  late FilesSplit split;
  late CollectionActions collectionActions;
  late bool isCollectionOwner;
  // Reuse the link while the selection is unchanged.
  Collection? _cachedCollectionForSharedLink;
  final GlobalKey shareButtonKey = GlobalKey();
  final GlobalKey sendLinkButtonKey = GlobalKey();
  final StreamController<double> _progressController =
      StreamController<double>();
  final DeviceFolderTransferClient _deviceFolderTransferClient =
      DeviceFolderTransferClient();
  Set<DeviceFolderTransferOperation> _supportedDeviceFolderTransferOperations =
      const {};
  bool _isDeviceFolderTransferInProgress = false;
  StreamSubscription<BackupUpdatedEvent>? _backupUpdatedSubscription;

  DeviceCollection? get _deviceFolderTransferSource => widget.deviceCollection;

  bool get _canTransferWithinDeviceFolders =>
      DeviceFolderTransferClient.isSupportedOnCurrentPlatform &&
      widget.type == GalleryType.localFolder &&
      _deviceFolderTransferSource != null;

  bool _supportsDeviceFolderTransfer(DeviceFolderTransferOperation operation) =>
      _canTransferWithinDeviceFolders &&
      _supportedDeviceFolderTransferOperations.contains(operation);

  bool get _hasPendingDeviceFolderMoveUploads {
    final pending = FileUploader.instance.allBackups;
    return widget.selectedFiles.files.any(
      (file) => file.localID != null && pending.containsKey(file.localID),
    );
  }

  bool get _canRemoveOthersFiles =>
      widget.collection != null &&
      CollectionsService.instance.canRemoveFilesFromAllParticipants(
        widget.collection!,
      );

  @override
  void initState() {
    super.initState();
    currentUserID = Configuration.instance.getUserID() ?? -1;

    split = FilesSplit.split(<EnteFile>[], currentUserID);
    widget.selectedFiles.addListener(_selectFileChangeListener);
    _backupUpdatedSubscription = Bus.instance.on<BackupUpdatedEvent>().listen(
      _onBackupUpdated,
    );
    collectionActions = CollectionActions(CollectionsService.instance);
    if (DeviceFolderTransferClient.isSupportedOnCurrentPlatform &&
        widget.type == GalleryType.localFolder) {
      unawaited(_loadSupportedDeviceFolderTransferOperations());
    }
    if (widget.selectedFiles.files.isNotEmpty) {
      _selectFileChangeListener();
    }
  }

  Future<void> _loadSupportedDeviceFolderTransferOperations() async {
    try {
      final supportedOperations = await _deviceFolderTransferClient
          .supportedOperations();
      if (!context.mounted) return;
      setState(() {
        _supportedDeviceFolderTransferOperations = supportedOperations;
      });
    } catch (error, stackTrace) {
      _logger.warning(
        'Could not load supported device-folder transfer operations',
        error,
        stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _backupUpdatedSubscription?.cancel();
    _progressController.close();
    widget.selectedFiles.removeListener(_selectFileChangeListener);
    super.dispose();
  }

  void _selectFileChangeListener() {
    if (_cachedCollectionForSharedLink != null) {
      _cachedCollectionForSharedLink = null;
    }
    split = FilesSplit.split(widget.selectedFiles.files, currentUserID);
    if (mounted) {
      setState(() => {});
    }
  }

  void _onBackupUpdated(BackupUpdatedEvent event) {
    if (!mounted) return;
    final changedLocalIDs = {...event.upserts.keys, ...event.removedLocalIDs};
    if (widget.selectedFiles.files.any(
      (file) => file.localID != null && changedLocalIDs.contains(file.localID),
    )) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedFiles.files.isEmpty) {
      return const SizedBox();
    }
    final ownedFilesCount = split.ownedByCurrentUser.length;
    final ownedAndPendingUploadFilesCount =
        ownedFilesCount + split.pendingUploads.length;
    final bool canRemoveOthersFiles = _canRemoveOthersFiles;
    final int removeCount =
        split.ownedByCurrentUser.length +
        (canRemoveOthersFiles ? split.ownedByOtherUsers.length : 0);

    final bool anyOwnedFiles =
        split.pendingUploads.isNotEmpty || split.ownedByCurrentUser.isNotEmpty;
    final bool allOwnedFiles =
        ownedAndPendingUploadFilesCount > 0 && split.ownedByOtherUsers.isEmpty;

    final bool anyUploadedFiles = split.ownedByCurrentUser.isNotEmpty;
    final bool hasUploadedFileIDs = widget.selectedFiles.files.any(
      (file) => file.uploadedFileID != null,
    );
    final showCollageOption =
        CollageCreatorPage.isValidCount(widget.selectedFiles.files.length) &&
        !widget.selectedFiles.files.any(
          (element) => element.fileType == FileType.video,
        );
    final showDownloadOption = hasUploadedFileIDs;
    final bool isCollectionOwnerOrAdmin =
        widget.collection != null &&
        (widget.collection!.isOwner(currentUserID) ||
            widget.collection!.isAdmin(currentUserID));
    final bool canSuggestDeleteAction =
        (widget.type == GalleryType.sharedCollection ||
            widget.type == GalleryType.ownedCollection) &&
        isCollectionOwnerOrAdmin &&
        split.ownedByOtherUsers.isNotEmpty;

    // Hidden items remain in the list so their removal can animate.
    final List<SelectionActionButton> items = [];
    if (widget.type == GalleryType.trash) {
      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedRestoreBin,
          labelText: context.strings.restore,
          onTap: _restore,
        ),
      );
      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          labelText: context.strings.permanentlyDelete,
          onTap: _permanentlyDeleteFromTrash,
          isCritical: true,
        ),
      );
    } else if (widget.type == GalleryType.cleanupHiddenFromDevice) {
      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          labelText: context.strings.deleteFromDevice,
          onTap: _deleteSelectedFromDevice,
          isCritical: true,
        ),
      );
    } else if (widget.type == GalleryType.deleteSuggestions) {
      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          labelText: context.strings.delete,
          onTap: split.ownedByCurrentUser.isNotEmpty ? _onDeleteClick : null,
          isCritical: true,
        ),
      );
      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedCancel01,
          labelText: context.strings.rejectSuggestions,
          onTap: widget.selectedFiles.files.isNotEmpty
              ? _rejectDeleteSuggestions
              : null,
        ),
      );
    } else {
      if (widget.type != GalleryType.sharedPublicCollection) {
        items.add(
          SelectionActionButton(
            labelText: context.strings.share,
            hugeIcon: Platform.isIOS
                ? HugeIcons.strokeRoundedShare03
                : HugeIcons.strokeRoundedShare08,
            key: shareButtonKey,
            onTap: _shareSelectedFiles,
          ),
        );
      }

      if (widget.type.showCreateLink()) {
        if (_cachedCollectionForSharedLink != null && anyUploadedFiles) {
          items.add(
            SelectionActionButton(
              hugeIcon: HugeIcons.strokeRoundedCopy01,
              labelText: context.strings.copyLink,
              onTap: anyUploadedFiles ? _sendLink : null,
            ),
          );
        } else {
          items.add(
            SelectionActionButton(
              hugeIcon: HugeIcons.strokeRoundedNavigation03,
              labelText: context.strings.sendLink,
              onTap: anyUploadedFiles ? _onSendLinkTapped : null,
              shouldShow: ownedFilesCount > 0,
              key: sendLinkButtonKey,
            ),
          );
        }
      }

      final showUploadIcon =
          widget.type == GalleryType.localFolder &&
          split.ownedByCurrentUser.isEmpty;
      if (widget.type.showAddToAlbum() && !isLocalGalleryMode) {
        if (showUploadIcon) {
          items.add(
            SelectionActionButton(
              hugeIcon: HugeIcons.strokeRoundedCloudUpload,
              labelText: context.strings.addToEnte,
              onTap: _addToAlbum,
            ),
          );
        } else {
          items.add(
            SelectionActionButton(
              hugeIcon: HugeIcons.strokeRoundedImageAdd01,
              labelText: context.strings.addToAlbum,
              onTap: _addToAlbum,
            ),
          );
        }
      }

      if (widget.type.showAddtoHiddenAlbum()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedImageAdd01,
            labelText: context.strings.addToAlbum,
            onTap: _addToHiddenAlbum,
          ),
        );
      }

      if (widget.type.showMoveToAlbum()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedArrowRight01,
            labelText: context.strings.moveToAlbum,
            onTap: anyUploadedFiles ? _moveFiles : null,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      }

      if (_supportsDeviceFolderTransfer(DeviceFolderTransferOperation.copy)) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedCopy01,
            labelText: context.strings.copyToAlbum,
            onTap: _isDeviceFolderTransferInProgress
                ? null
                : () => _transferToDeviceFolder(
                    DeviceFolderTransferOperation.copy,
                  ),
          ),
        );
      }
      if (_supportsDeviceFolderTransfer(DeviceFolderTransferOperation.move) &&
          !_hasPendingDeviceFolderMoveUploads) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedArrowRight01,
            labelText: context.strings.moveToAlbum,
            onTap: _isDeviceFolderTransferInProgress
                ? null
                : () => _transferToDeviceFolder(
                    DeviceFolderTransferOperation.move,
                  ),
          ),
        );
      }

      if (widget.type.showMovetoHiddenAlbum()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedArrowRight01,
            labelText: context.strings.moveToAlbum,
            onTap: _moveFilesToHiddenAlbum,
          ),
        );
      }

      if (widget.type.showRemoveFromAlbum()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedRemove01,
            labelText: context.strings.removeFromAlbum,
            onTap: removeCount > 0 ? _removeFilesFromAlbum : null,
            shouldShow: removeCount > 0,
          ),
        );
      }

      if (widget.type.showRemoveFromHiddenAlbum()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedRemove01,
            labelText: context.strings.removeFromAlbum,
            onTap: _removeFilesFromHiddenAlbum,
          ),
        );
      }

      if (canSuggestDeleteAction) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedFlag01,
            labelText: context.strings.suggestDeletion,
            onTap: _onSuggestDelete,
          ),
        );
      }

      if (widget.type.showDeleteOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedDelete01,
            labelText: context.strings.delete,
            onTap: anyOwnedFiles ? _onDeleteClick : null,
            shouldShow: allOwnedFiles,
            isCritical: true,
          ),
        );
      }

      if (widget.type.showRestoreOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedRestoreBin,
            labelText: context.strings.restore,
            onTap: _restore,
          ),
        );
      }

      if (widget.type.showPermanentlyDeleteOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedDelete01,
            labelText: context.strings.permanentlyDelete,
            onTap: _permanentlyDeleteFromTrash,
            isCritical: true,
          ),
        );
      }

      if (showDownloadOption) {
        items.add(
          SelectionActionButton(
            labelText: context.strings.download,
            hugeIcon: HugeIcons.strokeRoundedDownload01,
            onTap: () => _download(widget.selectedFiles.files.toList()),
          ),
        );
      }

      if (widget.type.showFavoriteOption()) {
        items.add(
          SelectionActionButton(
            iconWidget: const Icon(EnteIcons.favoriteStroke),
            labelText: context.strings.favorite,
            onTap: anyUploadedFiles ? _onFavoriteClick : null,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      } else if (widget.type.showUnFavoriteOption()) {
        items.add(
          SelectionActionButton(
            iconWidget: const Icon(EnteIcons.favoriteFilled),
            labelText: context.strings.removeFromFavorite,
            onTap: _onUnFavoriteClick,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      }

      if (flagService.manualTagFileToPerson &&
          widget.type.showAddToPersonOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedUserAdd01,
            labelText: context.strings.addToPerson,
            onTap: hasUploadedFileIDs ? _onAddFilesToPerson : null,
            shouldShow: hasUploadedFileIDs,
          ),
        );
      }

      if (widget.type == GalleryType.peopleTag && widget.person != null) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedUserRemove01,
            labelText: context.strings.notPersonLabel(
              name: widget.person!.data.name,
            ),
            onTap: _onNotpersonClicked,
          ),
        );
        if (ownedFilesCount == 1) {
          items.add(
            SelectionActionButton(
              hugeIcon: HugeIcons.strokeRoundedImage01,
              labelText: context.strings.useAsCover,
              onTap: anyUploadedFiles ? _setPersonCover : null,
            ),
          );
        }
      }

      if (widget.type == GalleryType.cluster && widget.clusterID != null) {
        items.add(
          SelectionActionButton(
            labelText: context.strings.notThisPerson,
            hugeIcon: HugeIcons.strokeRoundedUserRemove01,
            onTap: _onRemoveFromClusterClicked,
          ),
        );
      }

      if (widget.type != GalleryType.sharedPublicCollection) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedGridView,
            labelText: context.strings.createCollage,
            onTap: _onCreateCollageClicked,
            shouldShow: showCollageOption,
          ),
        );
      }

      if (widget.type.showHideOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedViewOffSlash,
            labelText: context.strings.hide,
            onTap: anyUploadedFiles ? _onHideClick : null,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      } else if (widget.type.showUnHideOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedView,
            labelText: context.strings.unhide,
            onTap: _onUnhideClick,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      }

      if (widget.type.showArchiveOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedArchive03,
            labelText: context.strings.archive,
            onTap: anyUploadedFiles ? _onArchiveClick : null,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      } else if (widget.type.showUnArchiveOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedUnarchive03,
            labelText: context.strings.unarchive,
            onTap: _onUnArchiveClick,
            shouldShow: ownedFilesCount > 0,
          ),
        );
      }

      if (widget.type.showRestoreOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedRestoreBin,
            labelText: context.strings.restore,
            onTap: _restore,
          ),
        );
      }

      if (widget.type.showPermanentlyDeleteOption()) {
        items.add(
          SelectionActionButton(
            hugeIcon: HugeIcons.strokeRoundedDelete01,
            labelText: context.strings.permanentlyDelete,
            onTap: _permanentlyDeleteFromTrash,
            isCritical: true,
          ),
        );
      }

      if (widget.type.showBulkEditTime()) {
        items.add(
          SelectionActionButton(
            shouldShow: widget.selectedFiles.files.every(
              (element) => (element.ownerID == currentUserID),
            ),
            labelText: context.strings.editTime,
            hugeIcon: HugeIcons.strokeRoundedDateTime,
            onTap: () async {
              final newDate = await showEditDateSheet(
                context,
                widget.selectedFiles.files,
              );
              if (newDate != null) {
                widget.selectedFiles.clearAll();
              }
            },
          ),
        );
      }

      if (widget.type.showEditLocation()) {
        items.add(
          SelectionActionButton(
            shouldShow: widget.selectedFiles.files.any(
              (element) => (element.ownerID == currentUserID),
            ),
            labelText: context.strings.editLocation,
            hugeIcon: HugeIcons.strokeRoundedMapsEditing,
            onTap: _editLocation,
          ),
        );
      }

      items.add(
        SelectionActionButton(
          hugeIcon: HugeIcons.strokeRoundedIncognito,
          labelText: context.strings.guestView,
          onTap: _onGuestViewClick,
        ),
      );
    }

    if (items.isNotEmpty) {
      final scrollController = ScrollController();
      // h4ck: https://github.com/flutter/flutter/issues/57920#issuecomment-893970066
      return MediaQuery(
        data: MediaQuery.of(context).removePadding(removeBottom: true),
        child: SafeArea(
          top: false,
          child: Scrollbar(
            radius: const Radius.circular(1),
            thickness: 2,
            controller: scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                decelerationRate: ScrollDecelerationRate.fast,
              ),
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 4),
                    ...items,
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }

  Future<void> _editLocation() async {
    await showBarModalBottomSheet(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
      ),
      backgroundColor: getEnteColorScheme(context).backgroundElevated,
      barrierColor: backdropFaintDark,
      topControl: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            width: double.infinity,
            height: 36,
            color: Colors.transparent,
          ),
          Container(
            height: 5,
            width: 40,
            decoration: const BoxDecoration(
              color: backgroundElevated2Light,
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
          ),
        ],
      ),
      context: context,
      builder: (context) {
        return UpdateLocationDataWidget(widget.selectedFiles.files.toList());
      },
    );
  }

  Future<void> _shareSelectedFiles() async {
    shareSelected(context, shareButtonKey, widget.selectedFiles.files.toList());
    widget.selectedFiles.clearAll();
  }

  Future<void> _moveFiles() async {
    if (split.pendingUploads.isNotEmpty || split.ownedByOtherUsers.isNotEmpty) {
      widget.selectedFiles.unSelectAll(
        split.pendingUploads.toSet(),
        skipNotify: true,
      );
      widget.selectedFiles.unSelectAll(
        split.ownedByOtherUsers.toSet(),
        skipNotify: true,
      );
    }
    await showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
      actionType: CollectionActionType.moveFiles,
    );
  }

  Future<void> _transferToDeviceFolder(
    DeviceFolderTransferOperation operation,
  ) async {
    if (!_supportsDeviceFolderTransfer(operation)) return;
    final source = _deviceFolderTransferSource;
    if (source == null) return;
    final selected = widget.selectedFiles.files.toList();
    final localIDs = selected
        .map((file) => file.localID)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (localIDs.isEmpty) return;
    try {
      final destination = await showDeviceFolderActionSheet(
        context,
        title: operation == DeviceFolderTransferOperation.move
            ? context.strings.moveToAlbum
            : context.strings.copyToAlbum,
        destinations: _loadDeviceFolderDestinations(
          source,
          operation,
          localIDs,
        ),
      );
      if (destination == null || !context.mounted) return;
      final effectiveSource =
          (await FilesDB.instance.getDeviceCollections()).firstWhereOrNull(
            (folder) => folder.id == source.id,
          ) ??
          source;
      final uploadedSourceLocalIDs = await FilesDB.instance.getUploadedLocalIDs(
        localIDs,
      );
      if (!context.mounted) return;
      final backedUpFileCount = uploadedSourceLocalIDs.length;
      if (operation == DeviceFolderTransferOperation.copy &&
          destination.shouldBackup &&
          backedUpFileCount > 0) {
        if (!mounted) return;
        final confirmed = await showBackedUpDeviceFolderCopyWarningSheet(
          context,
          backedUpFileCount: backedUpFileCount,
        );
        if (!confirmed || !context.mounted) return;
      }
      ConfirmedDeviceFolderMovePlan? confirmedMovePlan;
      if (operation == DeviceFolderTransferOperation.move) {
        final candidatePlan = await DeviceFolderConfirmedMovePlanner.instance
            .planDeviceMove(
              source: effectiveSource,
              destination: destination,
              localIDs: localIDs,
            );
        if (!mounted) return;
        if (candidatePlan != null && candidatePlan.entries.isNotEmpty) {
          final preference = localSettings.getLinkedDeviceMovePreference();
          if (preference == LinkedDeviceMovePreference.both) {
            confirmedMovePlan = candidatePlan;
          } else if (preference == LinkedDeviceMovePreference.ask) {
            final choice = await showLinkedDeviceMoveSheet(
              context,
              previews: selected,
              linkedLocalIDs: candidatePlan.entries
                  .map((entry) => entry.localID)
                  .toSet(),
              selectedCount: localIDs.length,
              eligibleCount: candidatePlan.entries.length,
              deviceInitiated: true,
            );
            if (choice == null || !mounted) return;
            if (choice.remember) {
              await localSettings.setLinkedDeviceMovePreference(
                choice.includeLinkedSide
                    ? LinkedDeviceMovePreference.both
                    : LinkedDeviceMovePreference.primaryOnly,
              );
            }
            if (choice.includeLinkedSide) confirmedMovePlan = candidatePlan;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _isDeviceFolderTransferInProgress = true;
      });
      final dialog = createProgressDialog(
        context,
        operation == DeviceFolderTransferOperation.move
            ? context.strings.movingItemsTo(
                count: localIDs.length,
                albumName: destination.name,
              )
            : context.strings.copyingItemsTo(
                count: localIDs.length,
                albumName: destination.name,
              ),
      );
      await dialog.show();
      late final DeviceFolderTransferResult result;
      try {
        result = await DeviceFolderTransferCoordinator.instance.transfer(
          source: effectiveSource,
          destination: destination,
          request: DeviceFolderTransferRequest(
            operation: operation,
            sourceFolderID: effectiveSource.id,
            targetFolderID: destination.id,
            sourceLocalIDs: localIDs,
          ),
          confirmedMovePlan: confirmedMovePlan,
        );
        if (result.wasCancelled) return;
      } finally {
        await dialog.hide();
        if (mounted) {
          setState(() {
            _isDeviceFolderTransferInProgress = false;
          });
        }
      }
      if (!mounted) return;
      final failures = result.failures.length;
      final localReconciliationFailureCount = result.localReconciliationFailed
          ? result.successLocalIDs.length
          : 0;
      if (failures == 0 &&
          !result.localReconciliationFailed &&
          result.successLocalIDs.isNotEmpty) {
        widget.selectedFiles.clearAll();
        showShortToast(
          context,
          operation == DeviceFolderTransferOperation.move
              ? context.strings.movedItemsTo(
                  count: result.successLocalIDs.length,
                  albumName: destination.name,
                )
              : context.strings.copiedItemsTo(
                  count: result.successLocalIDs.length,
                  albumName: destination.name,
                ),
        );
      } else if (result.successLocalIDs.isNotEmpty) {
        widget.selectedFiles.unSelectAll(
          selected
              .where((file) => result.successLocalIDs.contains(file.localID))
              .toSet(),
        );
        showToast(
          context,
          context.strings.partiallyTransferredItems(
            completedCount: result.successLocalIDs.length,
            failedCount: failures + localReconciliationFailureCount,
          ),
        );
      } else {
        showToast(context, context.strings.somethingWentWrongPleaseTryAgain);
      }
      _logger.info(
        'Device folder transfer completed: operation=${operation.name}, '
        'success=${result.successLocalIDs.length}, failures=$failures, '
        'localReconciliationFailed=${result.localReconciliationFailed}, '
        'categories=${result.failures.values.map((value) => value.name).toSet()}',
      );
      if (result.destinations.isNotEmpty && mounted) {
        final destinationFolder =
            (await FilesDB.instance.getDeviceCollections()).firstWhereOrNull(
              (folder) => folder.id == destination.id,
            ) ??
            destination;
        if (!mounted) return;
        await routeToPage(context, DeviceFolderPage(destinationFolder));
      }
    } catch (error, stackTrace) {
      _logger.severe(
        'Device folder transfer failed: operation=${operation.name}, count=${localIDs.length}',
        error,
        stackTrace,
      );
      if (mounted) {
        showToast(context, context.strings.somethingWentWrongPleaseTryAgain);
      }
    }
  }

  Future<List<DeviceCollection>> _loadDeviceFolderDestinations(
    DeviceCollection source,
    DeviceFolderTransferOperation operation,
    List<String> sourceLocalIDs,
  ) async {
    final folders = await FilesDB.instance.getDeviceCollections(
      includeCoverThumbnail: true,
    );
    final candidates = folders
        .where((folder) => folder.id != source.id && folder.thumbnail != null)
        .toList();
    final eligibleIDs = await _deviceFolderTransferClient
        .eligibleDestinationIDs(
          sourceFolderID: source.id,
          operation: operation,
          sourceLocalIDs: sourceLocalIDs,
          candidateFolderIDs: candidates.map((folder) => folder.id).toList(),
        );
    return candidates
        .where((folder) => eligibleIDs.contains(folder.id))
        .toList();
  }

  Future<void> _moveFilesToHiddenAlbum() async {
    await showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
      actionType: CollectionActionType.moveToHiddenCollection,
    );
  }

  Future<void> _addToAlbum() async {
    await showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
    );
  }

  Future<void> _addToHiddenAlbum() async {
    await showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
      actionType: CollectionActionType.addToHiddenAlbum,
    );
  }

  Future<void> _onDeleteClick() async {
    return showDeleteSheet(context, widget.selectedFiles, split);
  }

  Future<void> _rejectDeleteSuggestions() async {
    final fileIDs = widget.selectedFiles.files
        .map((file) => file.uploadedFileID)
        .whereType<int>()
        .toSet()
        .toList();
    if (fileIDs.isEmpty) {
      return;
    }
    try {
      await CollectionsService.instance.rejectDeleteSuggestions(fileIDs);
      widget.selectedFiles.clearAll();
      Bus.instance.fire(
        FilesUpdatedEvent(const [], source: "reject-delete-suggestions"),
      );
    } catch (e, s) {
      _logger.warning("Failed to reject delete suggestions", e, s);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onSuggestDelete() async {
    if (widget.collection == null) {
      return;
    }
    final List<EnteFile> filesToSuggest = split.ownedByOtherUsers
        .where((file) => file.uploadedFileID != null)
        .toList();
    if (filesToSuggest.isEmpty) {
      return;
    }
    final didSuggestDelete = await showSuggestDeleteSheet(
      context: context,
      onConfirm: () async {
        await CollectionsService.instance.suggestDeleteFromCollection(
          widget.collection!.id,
          filesToSuggest,
        );
      },
    );
    if (didSuggestDelete) {
      widget.selectedFiles.clearAll();
      if (mounted) {
        setState(() => {});
      }
    }
  }

  Future<void> _removeFilesFromAlbum() async {
    if (split.pendingUploads.isNotEmpty) {
      widget.selectedFiles.unSelectAll(
        split.pendingUploads.toSet(),
        skipNotify: true,
      );
    }
    if (!_canRemoveOthersFiles && split.ownedByOtherUsers.isNotEmpty) {
      widget.selectedFiles.unSelectAll(
        split.ownedByOtherUsers.toSet(),
        skipNotify: true,
      );
    }
    final bool removingOthersFile =
        _canRemoveOthersFiles && split.ownedByOtherUsers.isNotEmpty;
    await collectionActions.showRemoveFromCollectionSheetV2(
      context,
      widget.collection!,
      widget.selectedFiles,
      removingOthersFile,
    );
  }

  Future<void> _removeFilesFromHiddenAlbum() async {
    await collectionActions.showRemoveFromCollectionSheetV2(
      context,
      widget.collection!,
      widget.selectedFiles,
      false,
      isHidden: true,
    );
  }

  Future<void> _onFavoriteClick() async {
    final result = await collectionActions.updateFavorites(
      context,
      split.ownedByCurrentUser,
      true,
    );
    if (result) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _onUnFavoriteClick() async {
    final result = await collectionActions.updateFavorites(
      context,
      split.ownedByCurrentUser,
      false,
    );
    if (result) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _onAddFilesToPerson() async {
    final filesWithIds = widget.selectedFiles.files
        .where((file) => file.uploadedFileID != null)
        .toList();
    if (filesWithIds.isEmpty) {
      showShortToast(
        context,
        context.strings.onlyUploadedFilesCanBeAddedToPerson,
      );
      return;
    }
    final namedPersons = await AddFilesToPersonPage.prefetchNamedPersons(
      context,
    );
    if (!mounted) {
      return;
    }
    if (namedPersons != null && namedPersons.isEmpty) {
      return;
    }
    final result = await routeToPage(
      context,
      AddFilesToPersonPage(files: filesWithIds, initialPersons: namedPersons),
      forceCustomPageRoute: true,
    );
    if (result is! ManualPersonAssignmentResult) {
      return;
    }
    final addedCount = result.addedFileIds.length;
    if (addedCount > 0) {
      final addedFiles = filesWithIds
          .where(
            (file) =>
                file.uploadedFileID != null &&
                result.addedFileIds.contains(file.uploadedFileID),
          )
          .toList();
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "manual-add-files-to-person",
          person: result.person,
          relevantFiles: addedFiles,
        ),
      );
      if (!mounted) return;
      showToast(
        context,
        context.strings.addedFilesToPerson(
          count: addedCount,
          personName: result.person.data.name,
        ),
      );
      widget.selectedFiles.clearAll();
      if (mounted) {
        setState(() => {});
      }
      return;
    }
    final alreadyCount = result.alreadyAssignedFileIds.length;
    if (alreadyCount > 0) {
      if (!mounted) return;
      showShortToast(
        context,
        context.strings.filesAlreadyLinkedToPerson(
          count: alreadyCount,
          personName: result.person.data.name,
        ),
      );
    }
  }

  Future<void> _onGuestViewClick() async {
    final List<EnteFile> selectedFiles = widget.selectedFiles.files.toList();
    final isDeviceSupported = await LocalAuthentication().isDeviceSupported();
    if (!mounted) return;
    if (isDeviceSupported) {
      final page = DetailPage(
        DetailPageConfiguration(
          selectedFiles,
          0,
          "guest_view",
          galleryType: widget.type,
        ),
      );
      await localSettings.setOnGuestView(true);
      if (!mounted) return;
      routeToPage(context, page, forceCustomPageRoute: true).ignore();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Bus.instance.fire(GuestViewEvent(true, false));
      });
    } else {
      await showErrorDialog(
        context,
        context.strings.noSystemLockFound,
        context.strings.guestViewEnablePreSteps,
      );
    }
    if (!mounted) return;
    widget.selectedFiles.clearAll();
  }

  Future<void> _onArchiveClick() async {
    await changeVisibility(
      context,
      split.ownedByCurrentUser,
      archiveVisibility,
    );
    widget.selectedFiles.clearAll();
  }

  Future<void> _onUnArchiveClick() async {
    await changeVisibility(
      context,
      split.ownedByCurrentUser,
      visibleVisibility,
    );
    widget.selectedFiles.clearAll();
  }

  Future<void> _onHideClick() async {
    await CollectionsService.instance.hideFiles(
      context,
      split.ownedByCurrentUser,
    );
    widget.selectedFiles.clearAll();
  }

  Future<void> _onUnhideClick() async {
    if (split.pendingUploads.isNotEmpty || split.ownedByOtherUsers.isNotEmpty) {
      widget.selectedFiles.unSelectAll(
        split.pendingUploads.toSet(),
        skipNotify: true,
      );
      widget.selectedFiles.unSelectAll(
        split.ownedByOtherUsers.toSet(),
        skipNotify: true,
      );
    }
    await showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
      actionType: CollectionActionType.unHide,
    );
  }

  Future<void> _onCreateCollageClicked() async {
    final bool? result = await routeToPage(
      context,
      CollageCreatorPage(widget.selectedFiles.files.toList()),
    );
    if (result != null && result) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _onSendLinkTapped() async {
    if (split.ownedByCurrentUser.isEmpty) {
      showShortToast(
        context,
        context.strings.canOnlyCreateLinkForFilesOwnedByYou,
      );
      return;
    }
    final dialog = createProgressDialog(
      context,
      context.strings.creatingLink,
      isDismissible: true,
    );
    await dialog.show();
    if (!mounted) {
      await dialog.hide();
      return;
    }
    _cachedCollectionForSharedLink ??= await collectionActions
        .createSharedCollectionLink(context, split.ownedByCurrentUser);

    if (!mounted) {
      await dialog.hide();
      return;
    }
    if (_cachedCollectionForSharedLink == null) {
      await dialog.hide();
      return;
    }
    await dialog.hide();
    if (!mounted) return;
    await _sendLink();
    if (!mounted) return;
    widget.selectedFiles.clearAll();
    setState(() => {});
  }

  Future<void> _setPersonCover() async {
    final EnteFile file = widget.selectedFiles.files.first;
    final result = await PersonService.instance.updateAvatar(
      widget.person!,
      file,
    );
    final updatedPerson = result.person;
    widget.selectedFiles.clearAll();
    if (mounted) {
      setState(() => {});
      if (result.contactPictureUpdateFailed) {
        showShortToast(context, "Failed to update contact picture");
      }
    }
    Bus.instance.fire(
      PeopleChangedEvent(
        type: PeopleEventType.saveOrEditPerson,
        source: "setPersonCover",
        person: updatedPerson,
      ),
    );
  }

  Future<void> _onNotpersonClicked() async {
    try {
      final actionResult = await showActionSheet(
        context: context,
        title: context.strings.removeFromPersonQuestion,
        buttons: [
          ButtonWidget(
            labelText: context.strings.yesRemove,
            buttonType: ButtonType.neutral,
            buttonSize: ButtonSize.large,
            shouldStickToDarkTheme: true,
            buttonAction: ButtonAction.first,
            isInAlert: true,
          ),
          ButtonWidget(
            labelText: context.strings.cancel,
            buttonType: ButtonType.secondary,
            buttonSize: ButtonSize.large,
            buttonAction: ButtonAction.second,
            shouldStickToDarkTheme: true,
            isInAlert: true,
          ),
        ],
        body: context.strings.selectedItemsWillBeRemovedFromThisPerson,
        actionSheetType: ActionSheetType.defaultActionSheet,
      );
      if (actionResult?.action != null) {
        if (actionResult!.action == ButtonAction.first) {
          await ClusterFeedbackService.instance.removeFilesFromPerson(
            widget.selectedFiles.files.toList(),
            widget.person!,
          );
        }
      }
      widget.selectedFiles.clearAll();
      if (mounted) {
        setState(() => {});
      }
    } catch (e, s) {
      _logger.severe("Failed to initiate `notPersonLabel`", e, s);
    }
  }

  Future<void> _onRemoveFromClusterClicked() async {
    if (widget.clusterID == null) {
      showShortToast(context, 'Cluster ID is null. Cannot remove files.');
      return;
    }
    final actionResult = await showActionSheet(
      context: context,
      title: context.strings.removeFromPersonQuestion,
      buttons: [
        ButtonWidget(
          labelText: context.strings.yesRemove,
          buttonType: ButtonType.neutral,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          isInAlert: true,
        ),
        ButtonWidget(
          labelText: context.strings.cancel,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          buttonAction: ButtonAction.second,
          shouldStickToDarkTheme: true,
          isInAlert: true,
        ),
      ],
      body: context.strings.selectedItemsWillBeRemovedFromThisPerson,
      actionSheetType: ActionSheetType.defaultActionSheet,
    );
    if (actionResult?.action != null) {
      if (actionResult!.action == ButtonAction.first) {
        await ClusterFeedbackService.instance.removeFilesFromCluster(
          widget.selectedFiles.files.toList(),
          widget.clusterID!,
        );
      }
    }
    widget.selectedFiles.clearAll();
    if (mounted) {
      setState(() => {});
    }
  }

  Future<void> _sendLink() async {
    if (_cachedCollectionForSharedLink != null) {
      final String url = CollectionsService.instance.getPublicUrl(
        _cachedCollectionForSharedLink!,
      );
      unawaited(Clipboard.setData(ClipboardData(text: url)));
      await shareLinkWithDescription(
        url,
        context: context,
        key: sendLinkButtonKey,
      );
    }
  }

  void _restore() {
    final isDeviceOnly = widget.selectedFiles.files.every(
      (f) => f.isDeviceTrash,
    );
    if (isDeviceOnly) {
      _restoreFilesFromDeviceTrash(widget.selectedFiles)
          .then((restoredCount) {
            if (restoredCount == 0 || !mounted) return;
            showToast(
              context,
              context.strings.restoredItems(count: restoredCount),
            );
          })
          .onError((e, s) {
            if (!mounted) return;
            showGenericErrorDialog(context: context, error: e).ignore();
          });
      return;
    }
    showCollectionActionSheet(
      context,
      selectedFiles: widget.selectedFiles,
      actionType: CollectionActionType.restoreFiles,
    );
  }

  Future<void> _permanentlyDeleteFromTrash() async {
    final isDeviceOnly = widget.selectedFiles.files.every(
      (f) => f.isDeviceTrash,
    );
    if (isDeviceOnly) {
      final deletedIDs = await permanentlyDeleteFromDeviceTrash(
        context,
        widget.selectedFiles.files.map((f) => f.localID!).toList(),
      );
      widget.selectedFiles.unSelectAll(
        widget.selectedFiles.files
            .where((f) => deletedIDs.contains(f.localID))
            .toSet(),
      );
      return;
    }
    if (await deleteFromEnteTrash(
      context,
      widget.selectedFiles.files.whereType<EnteTrashFile>().toList(),
    )) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _deleteSelectedFromDevice() async {
    final filesToDelete = widget.selectedFiles.files.toList();
    final l10n = context.strings;

    final actionResult = await showActionSheet(
      context: context,
      title: l10n.deleteFromDeviceQuestion,
      buttons: [
        ButtonWidget(
          labelText: l10n.deleteFromDevice,
          buttonType: ButtonType.neutral,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          isInAlert: true,
          onTap: () async {
            try {
              await deleteFilesOnDeviceOnly(context, filesToDelete);
            } catch (e) {
              if (mounted) {
                await showGenericErrorDialog(context: context, error: e);
              }
              rethrow;
            }
          },
        ),
        ButtonWidget(
          labelText: l10n.cancel,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
        ),
      ],
      body: l10n.theseItemsWillBeDeletedFromYourDevice,
      actionSheetType: ActionSheetType.defaultActionSheet,
    );

    if (actionResult?.action == ButtonAction.first) {
      widget.selectedFiles.clearAll();
      if (mounted) {
        await showMediaManagementHintSheet(context);
      }
    }
  }

  Future<void> _download(List<EnteFile> files) async {
    if (files.isEmpty) {
      return;
    }

    final l10n = context.strings;
    final existingLocalFolderNames = await Future.wait(
      files.map((file) => getExistingLocalFolderNameForDownloadSkipToast(file)),
    );
    if (!mounted) return;

    final filesToDownload = <EnteFile>[];
    final skippedFiles = <EnteFile>[];
    String? skippedSingleFolderName;
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final existingLocalFolderName = existingLocalFolderNames[i];
      if (existingLocalFolderName != null) {
        skippedFiles.add(file);
        skippedSingleFolderName = existingLocalFolderName;
        continue;
      }
      filesToDownload.add(
        file.isRemoteOnlyFile
            ? file.copyWith()
            : (file.copyWith()..localID = null),
      );
    }
    final skippedFilesCount = skippedFiles.length;
    int addedToQueueCount = 0;

    if (filesToDownload.isNotEmpty) {
      if (!await ensurePhotoLibraryAddPermission(context)) return;
      if (!mounted) return;

      if (flagService.internalUser) {
        try {
          final enqueueResult = await galleryDownloadQueueService.enqueueFiles(
            filesToDownload,
            persistToFilesDB: widget.type != GalleryType.sharedPublicCollection,
          );
          addedToQueueCount = enqueueResult.addedCount;
        } catch (e) {
          _logger.warning("Failed to enqueue files for download", e);
          if (!mounted) return;
          await showGenericErrorDialog(context: context, error: e);
          return;
        }
      } else {
        final totalFiles = filesToDownload.length;
        int downloadedFiles = 0;
        final downloadingMessage = l10n.downloading;

        final dialog = createProgressDialog(
          context,
          "$downloadingMessage ($downloadedFiles/$totalFiles)",
          isDismissible: true,
        );
        final didShowDialog = await dialog.show();
        try {
          final taskQueue = SimpleTaskQueue(maxConcurrent: 5);
          final futures = <Future>[];
          for (final file in filesToDownload) {
            futures.add(
              taskQueue.add(() async {
                await downloadToGallery(
                  file,
                  persistToFilesDB:
                      widget.type != GalleryType.sharedPublicCollection,
                );
                downloadedFiles++;
                if (didShowDialog) {
                  dialog.update(
                    message:
                        "$downloadingMessage ($downloadedFiles/$totalFiles)",
                  );
                }
              }),
            );
          }
          await Future.wait(futures);
          addedToQueueCount = downloadedFiles;
          if (didShowDialog) {
            await dialog.hide();
          }
        } catch (e, s) {
          _logger.warning("Failed to save files", e, s);
          if (didShowDialog) {
            await dialog.hide();
          }
          if (mounted) {
            await showGenericErrorDialog(context: context, error: e);
          }
          return;
        }
      }
    }

    if (!mounted) return;
    if (skippedFilesCount > 0) {
      String finalMessage;
      if (skippedFilesCount == 1) {
        final skippedFile = skippedFiles.first;
        finalMessage = l10n.downloadSkippedInSelectionSingleFile(
          fileName: getDownloadSkipToastFileName(skippedFile),
          albumName: skippedSingleFolderName ?? l10n.gallery,
        );
      } else {
        finalMessage = l10n.downloadSkippedInSelectionMultipleFiles(
          fileCount: skippedFilesCount,
        );
      }
      showToast(context, finalMessage, iosLongToastLengthInSec: 4);
    }

    if (!flagService.internalUser &&
        skippedFilesCount == 0 &&
        addedToQueueCount > 0) {
      showToast(
        context,
        context.strings.filesSavedToGallery,
        iosLongToastLengthInSec: 4,
      );
    }

    if (addedToQueueCount == 0 && skippedFilesCount == 0) {
      return;
    }

    if (skippedFilesCount == 0) {
      widget.selectedFiles.clearAll();
    } else {
      widget.selectedFiles.replaceSelection(skippedFiles.toSet());
    }
  }

  Future<int> _restoreFilesFromDeviceTrash(SelectedFiles selectedFiles) async {
    final files = selectedFiles.files
        .map((f) => f.asDeviceTrashFile!.toAssetEntity())
        .toList();
    final restoredIDs = <String>{};
    try {
      for (final batch in files.chunks(batchSize)) {
        final result = await PhotoManager.editor.android.restoreFromTrash(
          batch,
        );
        restoredIDs.addAll(result);
      }
      return restoredIDs.length;
    } catch (e, s) {
      _logger.warning("_restoreFilesFromDeviceTrash failed:", e, s);
      rethrow;
    } finally {
      if (restoredIDs.isNotEmpty) {
        final restoredFiles = selectedFiles.files.where(
          (f) => restoredIDs.contains(f.localID),
        );
        selectedFiles.unSelectAll(restoredFiles.toSet());
        Bus.instance.fire(ForceReloadTrashPageEvent());
      }
    }
  }
}
