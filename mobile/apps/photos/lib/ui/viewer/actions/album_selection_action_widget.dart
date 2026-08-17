import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_button_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/sharing/add_participant_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/magic_util.dart";

class AlbumSelectionActionWidget extends StatefulWidget {
  final SelectedAlbums selectedAlbums;
  final UISectionType sectionType;

  const AlbumSelectionActionWidget(
    this.selectedAlbums,
    this.sectionType, {
    super.key,
  });

  @override
  State<AlbumSelectionActionWidget> createState() =>
      _AlbumSelectionActionWidgetState();
}

class _AlbumSelectionActionWidgetState
    extends State<AlbumSelectionActionWidget> {
  final _logger = Logger("AlbumSelectionActionWidgetState");
  final _scrollController = ScrollController();
  late CollectionActions collectionActions;
  bool hasFavorites = false;

  @override
  initState() {
    collectionActions = CollectionActions(CollectionsService.instance);
    widget.selectedAlbums.addListener(_selectionChangedListener);
    super.initState();
  }

  @override
  void dispose() {
    widget.selectedAlbums.removeListener(_selectionChangedListener);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedAlbums.albums.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<SelectionActionButton> items = [];
    final hasPinnedAlbum = widget.selectedAlbums.albums.any(
      (album) => album.isPinned,
    );
    final hasUnpinnedAlbum = widget.selectedAlbums.albums.any(
      (album) => !album.isPinned,
    );

    if (widget.sectionType == UISectionType.homeCollections ||
        widget.sectionType == UISectionType.outgoingCollections) {
      items.add(
        SelectionActionButton(
          labelText: context.strings.share,
          hugeIcon: Platform.isIOS
              ? HugeIcons.strokeRoundedShare03
              : HugeIcons.strokeRoundedShare08,
          onTap: _shareCollection,
        ),
      );
      items.add(
        SelectionActionButton(
          labelText: context.strings.pin,
          hugeIcon: HugeIcons.strokeRoundedPin,
          onTap: _onPinClick,
          shouldShow: hasUnpinnedAlbum,
        ),
      );

      items.add(
        SelectionActionButton(
          labelText: context.strings.unpin,
          hugeIcon: HugeIcons.strokeRoundedPinOff,
          onTap: _onUnpinClick,
          shouldShow: hasPinnedAlbum,
        ),
      );

      items.add(
        SelectionActionButton(
          labelText: context.strings.delete,
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          onTap: _trashCollection,
          isCritical: true,
        ),
      );
      items.add(
        SelectionActionButton(
          labelText: context.strings.hide,
          hugeIcon: HugeIcons.strokeRoundedViewOffSlash,
          onTap: _onHideOrUnHideClick,
        ),
      );
    }

    if (widget.sectionType == UISectionType.archivedCollections) {
      items.add(
        SelectionActionButton(
          labelText: context.strings.unarchive,
          hugeIcon: HugeIcons.strokeRoundedUnarchive03,
          onTap: _archiveClick,
        ),
      );
      items.add(
        SelectionActionButton(
          labelText: context.strings.delete,
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          onTap: _trashCollection,
          isCritical: true,
        ),
      );
    } else if (widget.sectionType == UISectionType.hiddenCollections) {
      items.add(
        SelectionActionButton(
          labelText: context.strings.unhide,
          hugeIcon: HugeIcons.strokeRoundedView,
          onTap: _onHideOrUnHideClick,
        ),
      );
      items.add(
        SelectionActionButton(
          labelText: context.strings.delete,
          hugeIcon: HugeIcons.strokeRoundedDelete01,
          onTap: _trashCollection,
          isCritical: true,
        ),
      );
    } else {
      items.add(
        SelectionActionButton(
          labelText: context.strings.archive,
          hugeIcon: HugeIcons.strokeRoundedArchive03,
          onTap: _archiveClick,
        ),
      );
    }

    if (widget.sectionType == UISectionType.incomingCollections) {
      if (flagService.enableShareePin) {
        final hasShareePinnedAlbum = widget.selectedAlbums.albums.any(
          (album) => album.hasShareePinned(),
        );
        final hasShareeUnpinnedAlbum = widget.selectedAlbums.albums.any(
          (album) => !album.hasShareePinned(),
        );

        items.add(
          SelectionActionButton(
            labelText: context.strings.pin,
            hugeIcon: HugeIcons.strokeRoundedPin,
            onTap: _onPinClickForSharee,
            shouldShow: hasShareeUnpinnedAlbum,
          ),
        );

        items.add(
          SelectionActionButton(
            labelText: context.strings.unpin,
            hugeIcon: HugeIcons.strokeRoundedPinOff,
            onTap: _onUnpinClickForSharee,
            shouldShow: hasShareePinnedAlbum,
          ),
        );
      }

      items.add(
        SelectionActionButton(
          labelText: context.strings.hide,
          hugeIcon: HugeIcons.strokeRoundedViewOffSlash,
          onTap: _onHideOrUnHideClick,
        ),
      );

      items.add(
        SelectionActionButton(
          labelText: context.strings.leaveAlbum,
          hugeIcon: HugeIcons.strokeRoundedLogout05,
          onTap: _leaveAlbum,
        ),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).removePadding(removeBottom: true),
      child: SafeArea(
        child: Scrollbar(
          radius: const Radius.circular(1),
          thickness: 2,
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
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

  Future<void> _shareCollection() async {
    final actions = <ActionTypesToShow>[
      ActionTypesToShow.addViewer,
      ActionTypesToShow.addCollaborator,
      ActionTypesToShow.addAdmin,
    ];
    await routeToPage(
      context,
      AddParticipantPage(widget.selectedAlbums.albums.toList(), actions),
    );
    widget.selectedAlbums.clearAll();
  }

  Future<void> _trashCollection() async {
    int count = 0;
    final List<Collection> nonEmptyCollection = [];

    final List errors = [];
    final List<Collection> selectedAlbums = widget.selectedAlbums.albums.toList(
      growable: false,
    );
    for (final collection in selectedAlbums) {
      if (collection.type == CollectionType.favorites) {
        continue;
      }
      count = await FilesDB.instance.collectionFileCount(collection.id);
      if (!mounted) return;
      final bool isEmptyCollection = count == 0;
      if (isEmptyCollection) {
        try {
          await CollectionsService.instance.trashEmptyCollection(collection);
          if (!mounted) return;
        } catch (e, s) {
          _logger.warning("failed to trash collection", e, s);
          if (!mounted) return;
          errors.add(e);
        }
      } else {
        nonEmptyCollection.add(collection);
      }
    }
    if (errors.isNotEmpty) {
      await showGenericErrorDialog(context: context, error: errors.first);
      if (!mounted) return;
    }

    if (nonEmptyCollection.isNotEmpty) {
      final bool result = await collectionActions.deleteMultipleCollectionSheet(
        context,
        nonEmptyCollection,
      );
      if (result == false) {
        debugPrint("Failed to delete collection");
      }
    }
    if (!mounted) return;
    if (hasFavorites) {
      _showFavToast();
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _onPinClick() async {
    for (final collection in widget.selectedAlbums.albums) {
      if (collection.type == CollectionType.favorites || collection.isPinned) {
        continue;
      }

      await updateOrder(context, collection, collection.isPinned ? 1 : 1);
    }
    if (hasFavorites) {
      _showFavToast();
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _onUnpinClick() async {
    for (final collection in widget.selectedAlbums.albums) {
      if (collection.type == CollectionType.favorites || !collection.isPinned) {
        continue;
      }

      await updateOrder(context, collection, collection.isPinned ? 0 : 0);
    }
    if (hasFavorites) {
      _showFavToast();
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _onPinClickForSharee() async {
    for (final collection in widget.selectedAlbums.albums) {
      if (collection.hasShareePinned()) {
        continue;
      }

      await updateShareeOrder(context, collection, 1);
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _onUnpinClickForSharee() async {
    for (final collection in widget.selectedAlbums.albums) {
      if (!collection.hasShareePinned()) {
        continue;
      }

      await updateShareeOrder(context, collection, 0);
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _onHideOrUnHideClick() async {
    final userID = Configuration.instance.getUserID()!;
    final collections = widget.selectedAlbums.albums
        .where((c) => c.type != CollectionType.favorites)
        .toList();

    if (collections.isEmpty) {
      if (hasFavorites) {
        _showFavToast();
      }
      widget.selectedAlbums.clearAll();
      return;
    }

    final isUnhiding = collections.first.isHidden();
    if (!await prepareSharedAlbumsForHiding(
      context,
      collections.where(
        (collection) => collection.isOwner(userID) && !collection.isHidden(),
      ),
    )) {
      return;
    }
    if (!mounted) return;
    final dialog = createProgressDialog(
      context,
      isUnhiding ? context.strings.unhiding : context.strings.hiding,
    );
    await dialog.show();

    try {
      for (final collection in collections) {
        final isOwner = collection.isOwner(userID);
        final isHidden = collection.isHidden();
        final int prevVisiblity = isHidden
            ? hiddenVisibility
            : visibleVisibility;
        final int newVisiblity = isHidden
            ? visibleVisibility
            : hiddenVisibility;

        if (!mounted) return;
        await changeCollectionVisibility(
          context,
          collection: collection,
          newVisibility: newVisiblity,
          prevVisibility: prevVisiblity,
          isOwner: isOwner,
          showProgressDialog: false,
          skipSharedAlbumWarning: true,
        );
      }
      if (!mounted) return;
      showShortToast(
        context,
        isUnhiding
            ? context.strings.successfullyUnhid
            : context.strings.successfullyHid,
      );
    } catch (e, s) {
      _logger.warning("failed to change visibility", e, s);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    } finally {
      await dialog.hide();
    }

    if (hasFavorites) {
      _showFavToast();
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _archiveClick() async {
    final collections = widget.selectedAlbums.albums
        .where((c) => c.type != CollectionType.favorites)
        .toList();

    if (collections.isEmpty) {
      if (hasFavorites) {
        _showFavToast();
      }
      widget.selectedAlbums.clearAll();
      return;
    }

    final isUnarchiving =
        widget.sectionType == UISectionType.incomingCollections
        ? collections.first.hasShareeArchived()
        : collections.first.isArchived();
    final dialog = createProgressDialog(
      context,
      isUnarchiving ? context.strings.unarchiving : context.strings.archiving,
    );
    await dialog.show();

    try {
      for (final collection in collections) {
        if (widget.sectionType == UISectionType.incomingCollections) {
          final hasShareeArchived = collection.hasShareeArchived();
          final int prevVisiblity = hasShareeArchived
              ? archiveVisibility
              : visibleVisibility;
          final int newVisiblity = hasShareeArchived
              ? visibleVisibility
              : archiveVisibility;

          if (!mounted) return;
          await changeCollectionVisibility(
            context,
            collection: collection,
            newVisibility: newVisiblity,
            prevVisibility: prevVisiblity,
            isOwner: false,
            showProgressDialog: false,
          );
        } else {
          final isArchived = collection.isArchived();
          final int prevVisiblity = isArchived
              ? archiveVisibility
              : visibleVisibility;
          final int newVisiblity = isArchived
              ? visibleVisibility
              : archiveVisibility;

          if (!mounted) return;
          await changeCollectionVisibility(
            context,
            collection: collection,
            newVisibility: newVisiblity,
            prevVisibility: prevVisiblity,
            showProgressDialog: false,
          );
        }
      }
      if (!mounted) return;
      showShortToast(
        context,
        isUnarchiving
            ? context.strings.successfullyUnarchived
            : context.strings.successfullyArchived,
      );
    } catch (e, s) {
      _logger.warning("failed to change archive state", e, s);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    } finally {
      await dialog.hide();
    }

    if (hasFavorites) {
      _showFavToast();
    }
    if (mounted) {
      setState(() {});
    }
    widget.selectedAlbums.clearAll();
  }

  Future<void> _leaveAlbum() async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.critical,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: context.strings.leaveAlbum,
          onTap: () async {
            for (final collection in widget.selectedAlbums.albums) {
              await CollectionsService.instance.leaveAlbum(collection);
            }
            widget.selectedAlbums.clearAll();
          },
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: context.strings.cancel,
        ),
      ],
      title: context.strings.leaveSharedAlbum,
      body: context.strings.photosAddedByYouWillBeRemovedFromTheAlbum,
    );
    if (actionResult?.action != null && mounted) {
      if (actionResult!.action == ButtonAction.error) {
        await showGenericErrorDialog(
          context: context,
          error: actionResult.exception,
        );
      } else if (actionResult.action == ButtonAction.first) {
        Navigator.of(context).pop();
      }
    }
  }

  void _selectionChangedListener() {
    if (mounted) {
      hasFavorites = widget.selectedAlbums.albums.any(
        (album) => album.type == CollectionType.favorites,
      );
      setState(() {});
    }
  }

  void _showFavToast() {
    showShortToast(
      context,
      context.strings.actionNotSupportedOnFavouritesAlbum,
    );
  }
}
