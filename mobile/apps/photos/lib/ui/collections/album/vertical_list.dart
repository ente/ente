import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:ente_components/ente_components.dart";
import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/event_bus.dart";
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/events/create_new_album_event.dart";
import "package:photos/events/tab_changed_event.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/device_folder_confirmed_move_planner.dart';
import 'package:photos/services/device_folder_transfer_coordinator.dart';
import "package:photos/services/hidden_service.dart";
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:photos/settings/local_settings.dart';
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/collections/album/column_item.dart";
import "package:photos/ui/collections/album/new_list_item.dart";
import 'package:photos/ui/collections/collection_action_sheet.dart';
import 'package:photos/ui/collections/device/device_folder_action_sheet.dart';
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/sharing/share_collection_page.dart";
import 'package:photos/ui/viewer/gallery/collection_page.dart';
import "package:photos/ui/viewer/gallery/empty_state.dart";
import 'package:photos/utils/dialog_util.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class AlbumVerticalListWidget extends StatefulWidget {
  final List<Collection> collections;
  final List<Collection> recentCollections;
  final List<Collection> sharedCollections;
  final CollectionActionType actionType;
  final SelectedFiles? selectedFiles;
  final List<SharedMediaFile>? sharedFiles;
  final String searchQuery;
  final bool shouldShowCreateAlbum;
  final bool enableSelection;
  final List<Collection> selectedCollections;
  final Function()? onSelectionChanged;
  final List<String>? selectedPeople;
  final ScrollController? scrollController;

  const AlbumVerticalListWidget(
    this.collections,
    this.actionType,
    this.selectedFiles,
    this.sharedFiles,
    this.selectedPeople,
    this.searchQuery,
    this.shouldShowCreateAlbum, {
    required this.selectedCollections,
    this.recentCollections = const [],
    this.sharedCollections = const [],
    this.enableSelection = false,
    this.onSelectionChanged,
    this.scrollController,
    super.key,
  });

  @override
  State<AlbumVerticalListWidget> createState() =>
      _AlbumVerticalListWidgetState();
}

class _AlbumVerticalListWidgetState extends State<AlbumVerticalListWidget> {
  final _logger = Logger("CollectionsListWidgetState");

  final CollectionActions _collectionActions = CollectionActions(
    CollectionsService.instance,
  );

  @override
  Widget build(BuildContext context) {
    final filesCount = widget.sharedFiles != null
        ? widget.sharedFiles!.length
        : widget.selectedPeople != null
        ? widget.selectedPeople!.length
        : widget.selectedFiles?.files.length ?? 0;

    final hasRecentCollections = widget.recentCollections.isNotEmpty;
    final hasSharedCollections = widget.sharedCollections.isNotEmpty;

    if (widget.collections.isEmpty &&
        !hasRecentCollections &&
        !hasSharedCollections) {
      if (widget.shouldShowCreateAlbum) {
        return Align(
          alignment: Alignment.topCenter,
          child: _getNewAlbumWidget(context, filesCount),
        );
      }
      return const EmptyState();
    }

    final createAlbumOffset = widget.shouldShowCreateAlbum ? 1 : 0;
    final recentHeaderOffset = hasRecentCollections ? 1 : 0;
    final recentItemsCount = widget.recentCollections.length;
    final showDivider = hasRecentCollections && widget.collections.isNotEmpty;
    final dividerOffset = showDivider ? 1 : 0;
    final sharedHeaderOffset = hasSharedCollections ? 1 : 0;
    final sharedItemsCount = widget.sharedCollections.length;

    final totalItemCount =
        createAlbumOffset +
        recentHeaderOffset +
        recentItemsCount +
        dividerOffset +
        widget.collections.length +
        sharedHeaderOffset +
        sharedItemsCount;

    return ListView.separated(
      controller: widget.scrollController,
      itemBuilder: (context, index) {
        if (index == 0 && widget.shouldShowCreateAlbum) {
          return _getNewAlbumWidget(context, filesCount);
        }

        final adjustedIndex = index - createAlbumOffset;

        if (hasRecentCollections && adjustedIndex == 0) {
          return _buildSectionHeader(context, context.strings.recent);
        }

        final recentStartIndex = recentHeaderOffset;
        if (hasRecentCollections &&
            adjustedIndex >= recentStartIndex &&
            adjustedIndex < recentStartIndex + recentItemsCount) {
          final recentIndex = adjustedIndex - recentStartIndex;
          final item = widget.recentCollections[recentIndex];
          return _buildCollectionItem(context, item);
        }

        final dividerIndex = recentStartIndex + recentItemsCount;
        if (showDivider && adjustedIndex == dividerIndex) {
          return _buildDivider(context);
        }

        final collectionsStartIndex =
            recentStartIndex + recentItemsCount + dividerOffset;
        final collectionsEndIndex =
            collectionsStartIndex + widget.collections.length;
        if (adjustedIndex >= collectionsStartIndex &&
            adjustedIndex < collectionsEndIndex) {
          final collectionIndex = adjustedIndex - collectionsStartIndex;
          final item = widget.collections[collectionIndex];
          return _buildCollectionItem(context, item);
        }

        final sharedHeaderIndex = collectionsEndIndex;
        if (hasSharedCollections && adjustedIndex == sharedHeaderIndex) {
          return _buildSectionHeader(context, "Shared with you");
        }

        final sharedStartIndex = sharedHeaderIndex + sharedHeaderOffset;
        if (hasSharedCollections && adjustedIndex >= sharedStartIndex) {
          final sharedIndex = adjustedIndex - sharedStartIndex;
          final item = widget.sharedCollections[sharedIndex];
          return _buildSharedCollectionItem(context, item);
        }

        return const SizedBox.shrink();
      },
      separatorBuilder: (context, index) => const SizedBox(height: Spacing.sm),
      itemCount: totalItemCount,
      shrinkWrap: false,
      physics: const BouncingScrollPhysics(),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        title,
        style: TextStyles.large.copyWith(
          color: context.componentColors.textBase,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return const DividerComponent(
      padding: EdgeInsets.symmetric(vertical: Spacing.sm),
    );
  }

  Widget _buildCollectionItem(BuildContext context, Collection item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.enableSelection
          ? _toggleCollectionSelection(item)
          : _albumListItemOnTap(context, item),
      child: AlbumColumnItemWidget(
        item,
        selectedCollections: widget.selectedCollections,
      ),
    );
  }

  Widget _buildSharedCollectionItem(BuildContext context, Collection item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _sharedAlbumOnTap(context, item),
      child: AlbumColumnItemWidget(
        item,
        selectedCollections: widget.selectedCollections,
      ),
    );
  }

  Future<void> _sharedAlbumOnTap(BuildContext context, Collection item) async {
    final shouldAdd = await _showAddToSharedAlbumSheet(context);
    if (!shouldAdd) {
      return;
    }

    if (!context.mounted) return;
    final success = await _addToCollection(context, item.id, true);
    if (success) {
      if (!context.mounted) return;
      showShortToast(
        context,
        context.strings.addedSuccessfullyTo(albumName: item.displayName),
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      if (!context.mounted) return;
      await _navigateToCollection(context, item);
    }
  }

  Future<bool> _showAddToSharedAlbumSheet(BuildContext context) async {
    final l10n = context.strings;
    final result = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.cannotMoveToSharedAlbums,
        content: Text(
          l10n.cannotMoveToSharedAlbumsMessage,
          style: TextStyles.body.copyWith(
            color: sheetContext.componentColors.textLight,
          ),
        ),
        closeTooltip: l10n.close,
        closeResult: false,
        actions: [
          ButtonComponent(
            label: l10n.add,
            variant: ButtonComponentVariant.neutral,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              Navigator.of(sheetContext).pop(true);
            },
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _toggleCollectionSelection(Collection collection) async {
    if (widget.selectedCollections.contains(collection)) {
      widget.selectedCollections.remove(collection);
    } else {
      widget.selectedCollections.isEmpty
          ? await HapticFeedback.mediumImpact()
          : null;
      widget.selectedCollections.add(collection);
    }
    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!();
    }
    setState(() {});
  }

  Widget _getNewAlbumWidget(BuildContext context, int filesCount) {
    return NewAlbumListItemWidget(
      onTap: (context) async {
        await _createNewAlbumOnTap(context, filesCount);
      },
    );
  }

  Future<void> _createNewAlbumOnTap(
    BuildContext context,
    int filesCount,
  ) async {
    if (filesCount > 0) {
      final result = await showTextInputDialog(
        context,
        title: context.strings.albumTitle,
        submitButtonLabel: context.strings.ok,
        hintText: context.strings.enterAlbumName,
        onSubmit: (name) async {
          return await _nameAlbum(context, name);
        },
        showOnlyLoadingState: true,
        textCapitalization: TextCapitalization.words,
        popnavAfterSubmission: true,
      );
      if (result is Exception) {
        _logger.severe("Failed to name album", result);
        if (!context.mounted) return;
        await showGenericErrorDialog(context: context, error: result);
      }
    } else {
      Navigator.pop(context);
      showToast(context, context.strings.createAlbumActionHint);
      Bus.instance.fire(
        TabChangedEvent(0, TabChangedEventSource.collectionsPage),
      );
    }
  }

  Future<void> _nameAlbum(BuildContext context, String albumName) async {
    if (albumName.isNotEmpty) {
      bool hasVerifiedLock = false;
      late final Collection? collection;

      if (widget.actionType == CollectionActionType.moveToHiddenCollection ||
          widget.actionType == CollectionActionType.addToHiddenAlbum) {
        collection = await CollectionsService.instance.createHiddenAlbum(
          albumName,
        );
        hasVerifiedLock = true;
      } else {
        collection = await _createAlbum(albumName);
      }

      if (collection != null) {
        if (widget.enableSelection) {
          Bus.instance.fire(CreateNewAlbumEvent(collection));
        } else {
          if (!context.mounted) return;
          if (await _runCollectionAction(
            context,
            collection,
            showProgressDialog: false,
          )) {
            if (widget.actionType == CollectionActionType.restoreFiles) {
              if (!context.mounted) return;
              showShortToast(context, 'Restored files to album ' + albumName);
            } else {
              if (!context.mounted) return;
              showShortToast(context, "Album '" + albumName + "' created.");
            }

            if (!context.mounted) return;
            Navigator.pop(context);
            if (!context.mounted) return;
            Navigator.pop(context);

            if (!context.mounted) return;
            await _navigateToCollection(
              context,
              collection,
              hasVerifiedLock: hasVerifiedLock,
            );
          }
        }
      }
    }
  }

  Future<Collection?> _createAlbum(String albumName) async {
    Collection? collection;
    try {
      collection = await CollectionsService.instance.createAlbum(albumName);
    } catch (e, s) {
      _logger.severe("Failed to create album", e, s);
      rethrow;
    }
    return collection;
  }

  Future<void> _albumListItemOnTap(
    BuildContext context,
    Collection item,
  ) async {
    if (await _runCollectionAction(context, item)) {
      late final String toastMessage;
      bool shouldNavigateToCollection = false;
      bool hasVerifiedLock = false;

      if (widget.actionType == CollectionActionType.addFiles) {
        if (!context.mounted) return;
        toastMessage = context.strings.addedSuccessfullyTo(
          albumName: item.displayName,
        );
        shouldNavigateToCollection = true;
      } else if (widget.actionType == CollectionActionType.moveFiles ||
          widget.actionType == CollectionActionType.restoreFiles ||
          widget.actionType == CollectionActionType.unHide) {
        if (!context.mounted) return;
        toastMessage = context.strings.movedSuccessfullyTo(
          albumName: item.displayName,
        );
        shouldNavigateToCollection = true;
      } else if (widget.actionType ==
          CollectionActionType.moveToHiddenCollection) {
        if (!context.mounted) return;
        toastMessage = context.strings.movedSuccessfullyTo(
          albumName: item.displayName,
        );
        shouldNavigateToCollection = true;
        hasVerifiedLock = true;
      } else if (widget.actionType == CollectionActionType.addToHiddenAlbum) {
        if (!context.mounted) return;
        toastMessage = context.strings.addedSuccessfullyTo(
          albumName: item.displayName,
        );
        shouldNavigateToCollection = true;
        hasVerifiedLock = true;
      } else {
        toastMessage = "";
      }
      if (toastMessage.isNotEmpty) {
        if (!context.mounted) return;
        showShortToast(context, toastMessage);
      }
      if (shouldNavigateToCollection) {
        if (!context.mounted) return;
        Navigator.pop(context);
        if (!context.mounted) return;
        await _navigateToCollection(
          context,
          item,
          hasVerifiedLock: hasVerifiedLock,
        );
      }
    }
  }

  Future<bool> _runCollectionAction(
    BuildContext context,
    Collection collection, {
    bool showProgressDialog = true,
  }) async {
    switch (widget.actionType) {
      case CollectionActionType.addFiles:
      case CollectionActionType.addToHiddenAlbum:
      case CollectionActionType.autoAddPeople:
        return _addToCollection(context, collection.id, showProgressDialog);
      case CollectionActionType.moveFiles:
        return _moveFilesToCollection(
          context,
          collection.id,
          destinationCollection: collection,
        );
      case CollectionActionType.unHide:
        return _moveFilesToCollection(context, collection.id);
      case CollectionActionType.restoreFiles:
        return _restoreFilesToCollection(context, collection.id);
      case CollectionActionType.shareCollection:
        return _showShareCollectionPage(context, collection);
      case CollectionActionType.moveToHiddenCollection:
        return _moveFilesToCollection(context, collection.id);
    }
  }

  Future<void> _navigateToCollection(
    BuildContext context,
    Collection collection, {
    bool hasVerifiedLock = false,
  }) async {
    await routeToPage(
      context,
      CollectionPage(
        CollectionWithThumbnail(collection, null),
        hasVerifiedLock: hasVerifiedLock,
      ),
    );
  }

  Future<bool> _showShareCollectionPage(
    BuildContext context,
    Collection collection,
  ) {
    if (Configuration.instance.getUserID() == collection.owner.id) {
      unawaited(routeToPage(context, ShareCollectionPage(collection)));
    } else {
      showGenericErrorDialog(
        context: context,
        error: Exception("Can not share collection owned by others"),
      ).ignore();
      _logger.severe("Cannot share collections owned by others");
    }
    return Future.value(true);
  }

  Future<bool> _addToCollection(
    BuildContext context,
    int collectionID,
    bool showProgressDialog,
  ) async {
    final bool result = await _collectionActions.addToCollection(
      context,
      collectionID,
      showProgressDialog,
      selectedFiles: widget.selectedFiles?.files.toList(),
      sharedFiles: widget.sharedFiles,
    );
    if (result) {
      CollectionsService.instance.recordCollectionUsage(collectionID);
      widget.selectedFiles?.clearAll();
    }
    return result;
  }

  Future<bool> _moveFilesToCollection(
    BuildContext context,
    int toCollectionID, {
    Collection? destinationCollection,
  }) async {
    late final String message;
    if (widget.actionType == CollectionActionType.moveFiles ||
        widget.actionType == CollectionActionType.moveToHiddenCollection) {
      message = context.strings.movingFilesToAlbum;
    } else {
      message = context.strings.unhidingFilesToAlbum;
    }

    final fromCollectionID = widget.selectedFiles!.files.first.collectionID!;
    if (widget.actionType == CollectionActionType.moveFiles &&
        destinationCollection != null &&
        DeviceFolderTransferClient.isSupportedOnCurrentPlatform) {
      try {
        final handled = await _moveLinkedDeviceFolderFilesIfRequested(
          context,
          sourceCollectionID: fromCollectionID,
          destinationCollection: destinationCollection,
        );
        if (handled != null) return handled;
      } catch (error, stackTrace) {
        _logger.severe(
          "Could not prepare linked device-folder move",
          error,
          stackTrace,
        );
        if (!context.mounted) return false;
        await showGenericErrorDialog(context: context, error: error);
        return false;
      }
    }
    if (!context.mounted) return false;

    final dialog = createProgressDialog(context, message, isDismissible: true);
    await dialog.show();
    try {
      await CollectionsService.instance.move(
        widget.selectedFiles!.files.toList(),
        toCollectionID: toCollectionID,
        fromCollectionID: fromCollectionID,
      );
      await dialog.hide();
      CollectionsService.instance.recordCollectionUsage(toCollectionID);
      unawaited(RemoteSyncService.instance.sync(silently: true));
      widget.selectedFiles?.clearAll();

      return true;
    } on AssertionError catch (e) {
      await dialog.hide();
      if (!context.mounted) return false;
      // ignore: unawaited_futures
      showErrorDialog(context, context.strings.oops, e.message as String?);
      return false;
    } catch (e, s) {
      _logger.severe("Could not move to album", e, s);
      await dialog.hide();
      if (!context.mounted) return false;
      await showGenericErrorDialog(context: context, error: e);
      return false;
    }
  }

  Future<bool?> _moveLinkedDeviceFolderFilesIfRequested(
    BuildContext context, {
    required int sourceCollectionID,
    required Collection destinationCollection,
  }) async {
    final ownerID = Configuration.instance.getUserID();
    final sourceCollection = CollectionsService.instance.getCollectionByID(
      sourceCollectionID,
    );
    if (ownerID == null ||
        sourceCollection == null ||
        !sourceCollection.canLinkToDevicePath(ownerID) ||
        !destinationCollection.canLinkToDevicePath(ownerID)) {
      return null;
    }
    final folders = await FilesDB.instance.getDeviceCollections();
    List<DeviceCollection> linkedFolderFor(int collectionID) => folders
        .where(
          (folder) =>
              folder.shouldBackup && folder.collectionID == collectionID,
        )
        .toList(growable: false);
    final sourceFolders = linkedFolderFor(sourceCollectionID);
    final destinationFolders = linkedFolderFor(destinationCollection.id);
    if (sourceFolders.length != 1 || destinationFolders.length != 1) {
      return null;
    }
    final source = sourceFolders.single;
    final destination = destinationFolders.single;
    final selected = widget.selectedFiles!.files.toList(growable: false);
    final successfulDeviceLocalIDs = <String>{};
    final localIDs = selected
        .map((file) => file.localID)
        .whereType<String>()
        .toSet();
    final plan = await DeviceFolderConfirmedMovePlanner.instance.planDeviceMove(
      source: source,
      destination: destination,
      localIDs: localIDs,
    );
    if (plan == null || plan.entries.isEmpty) return null;
    if (!await _supportsDeviceFolderMove()) return null;
    if (!context.mounted) return false;

    final preference = localSettings.getLinkedDeviceMovePreference();
    bool includeDevice = preference == LinkedDeviceMovePreference.both;
    if (preference == LinkedDeviceMovePreference.ask) {
      if (!context.mounted) return false;
      final choice = await showLinkedDeviceMoveSheet(
        context,
        previews: selected,
        linkedLocalIDs: plan.entries.map((entry) => entry.localID).toSet(),
        selectedCount: selected.length,
        eligibleCount: plan.entries.length,
        deviceInitiated: false,
      );
      if (choice == null) return false;
      includeDevice = choice.includeLinkedSide;
      if (choice.remember) {
        await localSettings.setLinkedDeviceMovePreference(
          includeDevice
              ? LinkedDeviceMovePreference.both
              : LinkedDeviceMovePreference.primaryOnly,
        );
      }
    }
    if (!includeDevice) return null;
    if (!context.mounted) return false;
    final connections = await Connectivity().checkConnectivity();
    if (!context.mounted) return false;
    if (!connections.any((result) => result != ConnectivityResult.none)) {
      await showGenericErrorDialog(context: context, error: null);
      return false;
    }

    final dialog = createProgressDialog(
      context,
      context.strings.movingItemsTo(
        count: selected.length,
        albumName: destination.name,
      ),
    );
    await dialog.show();
    bool? wasFullyHandled;
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      final result = await DeviceFolderTransferCoordinator.instance.transfer(
        source: source,
        destination: destination,
        request: DeviceFolderTransferRequest(
          operation: DeviceFolderTransferOperation.move,
          sourceFolderID: source.id,
          targetFolderID: destination.id,
          sourceLocalIDs: plan.entries.map((entry) => entry.localID).toList(),
        ),
        confirmedMovePlan: plan,
      );
      successfulDeviceLocalIDs.addAll(result.successLocalIDs);
      if (result.localReconciliationFailed) {
        throw StateError(
          'Could not reconcile the completed device-folder move',
        );
      }
      if (!result.wasCancelled) {
        final eligibleLocalIDs = plan.entries
            .map((entry) => entry.localID)
            .toSet();
        final cloudOnlyFiles = selected
            .where((file) => !eligibleLocalIDs.contains(file.localID))
            .toList(growable: false);
        if (cloudOnlyFiles.isNotEmpty) {
          final filesReadyToMove = await Future.wait(
            cloudOnlyFiles.map(
              (file) => file.uploadedFileID == null
                  ? FileUploader.instance.upload(file, sourceCollectionID)
                  : Future.value(file),
            ),
          );
          await CollectionsService.instance.move(
            filesReadyToMove,
            toCollectionID: destinationCollection.id,
            fromCollectionID: sourceCollectionID,
          );
          CollectionsService.instance.recordCollectionUsage(
            destinationCollection.id,
          );
          unawaited(RemoteSyncService.instance.sync(silently: true));
        }
        final handledLocalIDs = {
          ...cloudOnlyFiles.map((file) => file.localID).whereType<String>(),
          ...result.successLocalIDs,
        };
        final handledFiles = {
          ...cloudOnlyFiles,
          ...selected.where((file) => handledLocalIDs.contains(file.localID)),
        };
        if (handledFiles.length == selected.length) {
          widget.selectedFiles?.clearAll();
        } else {
          widget.selectedFiles?.unSelectAll(handledFiles);
          if (context.mounted) {
            showToast(
              context,
              context.strings.partiallyTransferredItems(
                completedCount: handledFiles.length,
                failedCount: selected.length - handledFiles.length,
              ),
            );
          }
        }
        wasFullyHandled = handledFiles.length == selected.length;
      }
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    } finally {
      await dialog.hide();
    }
    if (failure != null) {
      _logger.severe(
        "Could not move linked device-folder files",
        failure,
        failureStackTrace,
      );
      if (!context.mounted) return false;
      if (successfulDeviceLocalIDs.isNotEmpty) {
        widget.selectedFiles?.unSelectAll(
          selected
              .where((file) => successfulDeviceLocalIDs.contains(file.localID))
              .toSet(),
        );
      }
      await showGenericErrorDialog(context: context, error: failure);
      return false;
    }
    return wasFullyHandled ?? false;
  }

  Future<bool> _supportsDeviceFolderMove() async {
    try {
      return (await DeviceFolderTransferClient().supportedOperations())
          .contains(DeviceFolderTransferOperation.move);
    } catch (error, stackTrace) {
      _logger.warning(
        'Could not load device-folder transfer capabilities',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<bool> _restoreFilesToCollection(
    BuildContext context,
    int toCollectionID,
  ) async {
    final dialog = createProgressDialog(
      context,
      context.strings.restoringFiles,
      isDismissible: true,
    );
    await dialog.show();
    try {
      await CollectionsService.instance.restore(
        toCollectionID,
        widget.selectedFiles!.files.toList(),
      );
      CollectionsService.instance.recordCollectionUsage(toCollectionID);
      unawaited(RemoteSyncService.instance.sync(silently: true));
      widget.selectedFiles?.clearAll();
      await dialog.hide();
      return true;
    } on AssertionError catch (e) {
      await dialog.hide();
      if (!context.mounted) return false;
      // ignore: unawaited_futures
      showErrorDialog(context, context.strings.oops, e.message as String?);
      return false;
    } catch (e, s) {
      _logger.severe("Could not move to album", e, s);
      await dialog.hide();
      if (!context.mounted) return false;
      await showGenericErrorDialog(context: context, error: e);
      return false;
    }
  }
}
