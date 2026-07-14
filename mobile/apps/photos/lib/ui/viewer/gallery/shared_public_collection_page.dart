import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/end_to_end_banner.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/public_link_layout_util.dart";

class SharedPublicCollectionPage extends StatefulWidget {
  final CollectionWithThumbnail c;
  final String tagPrefix;
  final List<EnteFile>? files;
  final bool shouldShowJoinDialog;

  const SharedPublicCollectionPage(
    this.c, {
    this.tagPrefix = "shared_public_collection",
    super.key,
    this.files,
    this.shouldShowJoinDialog = false,
  }) : assert(!(files == null), 'sharedLinkFiles cannot be empty');

  @override
  State<SharedPublicCollectionPage> createState() =>
      _SharedPublicCollectionPageState();
}

class _SharedPublicCollectionPageState
    extends State<SharedPublicCollectionPage> {
  final _selectedFiles = SelectedFiles();
  final galleryType = GalleryType.sharedPublicCollection;
  final logger = Logger("SharedPublicCollectionPage");
  @override
  void initState() {
    super.initState();
    logger.info("Init SharedPublicCollectionPage");

    // Show join dialog after the page is built if requested
    if (widget.shouldShowJoinDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showJoinDialog();
      });
    }
  }

  Future<void> _showJoinDialog() async {
    final result = await showChoiceDialog(
      context,
      title: context.l10n.joinAlbum,
      body: context.l10n.joinAlbumConfirmationDialogBody,
      firstButtonLabel: context.l10n.join,
    );
    if (result != null && result.action == ButtonAction.first) {
      if (!mounted) return;
      final dialog = createProgressDialog(
        context,
        context.l10n.pleaseWait,
        isDismissible: true,
      );
      await dialog.show();
      try {
        if (!mounted) return;
        await RemoteSyncService.instance.joinAndSyncCollection(
          context,
          widget.c.collection.id,
        );
        final c = CollectionsService.instance.getCollectionByID(
          widget.c.collection.id,
        );
        await dialog.hide();
        if (!mounted) return;
        Navigator.of(context).pop();
        if (!mounted) return;
        await routeToPage(
          context,
          CollectionPage(CollectionWithThumbnail(c!, null)),
        );
      } catch (e, s) {
        logger.severe("Failed to join public album", e, s);
        await dialog.hide();
        if (!mounted) return;
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logger.info("Building SharedPublicCollectionPage");
    final List<EnteFile>? initialFiles = widget.c.thumbnail != null
        ? [widget.c.thumbnail!]
        : null;

    // Determine groupType based on collection layout.
    // masonry/continuous (or unset) map to non-grouped rendering.
    final normalizedLayout = normalizePublicLinkLayout(
      widget.c.collection.pubMagicMetadata.layout,
    );
    final GroupType groupType = normalizedLayout == "masonry"
        ? GroupType.none
        : GroupType.day;
    final appBar = GalleryAppBarWidget.sliverConfig(
      galleryType,
      widget.c.collection.displayName,
      _selectedFiles,
      collection: widget.c.collection,
      files: widget.files,
    );

    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        widget.files!.sort(
          (a, b) => b.creationTime!.compareTo(a.creationTime!),
        );

        return FileLoadResult(widget.files!, false);
      },
      reloadEvent: Bus.instance.on<CollectionUpdatedEvent>().where(
        (event) => event.collectionID == widget.c.collection.id,
      ),
      forceReloadEvents: [
        Bus.instance.on<CollectionMetaEvent>().where(
          (event) =>
              event.id == widget.c.collection.id &&
              event.type == CollectionMetaEventType.sortChanged,
        ),
      ],
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      tagPrefix: widget.tagPrefix,
      selectedFiles: _selectedFiles,
      initialFiles: initialFiles,
      albumName: widget.c.collection.displayName,
      galleryType: galleryType,
      groupType: groupType,
      header:
          widget.c.collection.isJoinEnabled &&
              Configuration.instance.isLoggedIn()
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: EndToEndBanner(
                leadingIcon: Icons.people_outlined,
                title: context.l10n.joinAlbum,
                caption: widget.c.collection.isCollectEnabledForPublicLink()
                    ? context.l10n.joinAlbumSubtext
                    : context.l10n.joinAlbumSubtextViewer,
                trailingWidget: ButtonWidget(
                  buttonType: ButtonType.primary,
                  buttonSize: ButtonSize.small,
                  icon: null,
                  labelText: context.l10n.join,
                  shouldSurfaceExecutionStates: false,
                  onTap: _joinAlbum,
                ),
              ),
            )
          : null,
      sortAsyncFn: () => widget.c.collection.pubMagicMetadata.asc ?? false,
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
                  galleryType,
                  _selectedFiles,
                  collection: widget.c.collection,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _joinAlbum() async {
    final result = await showChoiceDialog(
      context,
      title: context.l10n.joinAlbum,
      body: context.l10n.joinAlbumConfirmationDialogBody,
      firstButtonLabel: context.l10n.join,
    );
    if (result != null && result.action == ButtonAction.first) {
      if (!mounted) return;
      final dialog = createProgressDialog(
        context,
        AppLocalizations.of(context).pleaseWait,
        isDismissible: true,
      );
      await dialog.show();
      try {
        if (!mounted) return;
        await RemoteSyncService.instance.joinAndSyncCollection(
          context,
          widget.c.collection.id,
        );
        final c = CollectionsService.instance.getCollectionByID(
          widget.c.collection.id,
        );
        await dialog.hide();
        if (!mounted) return;
        Navigator.of(context).pop();
        if (!mounted) return;
        await routeToPage(
          context,
          CollectionPage(CollectionWithThumbnail(c!, null)),
        );
      } catch (e, s) {
        logger.severe("Failed to join collection", e, s);
        await dialog.hide();
        if (!mounted) return;
        showToast(context, AppLocalizations.of(context).somethingWentWrong);
      }
    }
  }
}
