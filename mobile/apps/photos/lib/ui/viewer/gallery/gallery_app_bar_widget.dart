import 'dart:async';
import 'dart:io';

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:local_auth/local_auth.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/constants.dart";
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/magic_sort_change_event.dart";
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/device_collection.dart';
import "package:photos/models/file/file.dart";
import 'package:photos/models/freeable_space_info.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import "package:photos/services/files_service.dart";
import "package:photos/states/location_screen_state.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import "package:photos/ui/cast/cast.dart";
import "package:photos/ui/collections/album/smart_album_people.dart";
import "package:photos/ui/common/web_page.dart";
import 'package:photos/ui/components/action_sheet_widget.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import "package:photos/ui/map/map_screen.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/sharing/album_participants_page.dart';
import "package:photos/ui/sharing/manage_links_widget.dart";
import 'package:photos/ui/sharing/share_collection_page.dart';
import 'package:photos/ui/tools/free_space_page.dart';
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/hooks/add_photos_sheet.dart";
import 'package:photos/ui/viewer/gallery/hooks/pick_cover_photo.dart';
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/hierarchicial_search/app_bar_filter_chips.dart";
import "package:photos/ui/viewer/location/edit_location_sheet.dart";
import 'package:photos/utils/delete_file_util.dart';
import 'package:photos/utils/dialog_util.dart';
import "package:photos/utils/file_download_util.dart";
import 'package:photos/utils/magic_util.dart';

class GalleryAppBarWidget extends StatefulWidget {
  static const double toolbarHeight = kToolbarHeight;
  static const double _sliverExpandedHeight = 92.0;

  static Color backgroundColor(BuildContext context) {
    return getEnteColorScheme(context).backgroundColour;
  }

  static GalleryAppBarConfig sliverConfig(
    GalleryType type,
    String? title,
    SelectedFiles selectedFiles, {
    String? subtitle,
    DeviceCollection? deviceCollection,
    bool? isDeviceFolderBackedUp,
    Future<void> Function()? onDisableDeviceFolderBackup,
    Collection? collection,
    List<EnteFile>? files,
  }) {
    return GalleryAppBarConfig(
      sliverBuilder: (_) => GalleryAppBarWidget._(
        type,
        title,
        selectedFiles,
        subtitle: subtitle,
        deviceCollection: deviceCollection,
        isDeviceFolderBackedUp: isDeviceFolderBackedUp,
        onDisableDeviceFolderBackup: onDisableDeviceFolderBackup,
        collection: collection,
        files: files,
      ),
      geometryBuilder: (context) =>
          _resolveSliverGeometry(context, subtitle: subtitle),
    );
  }

  static HeaderAppBarGeometry _resolveSliverGeometry(
    BuildContext context, {
    String? subtitle,
  }) {
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    final isHierarchicalSearchable =
        inheritedSearchFilterData?.isHierarchicalSearchable ?? false;
    final bottomHeight = isHierarchicalSearchable
        ? AppBarFilterChips.preferredHeight(context)
        : 0.0;
    return SliverAppBarComponent.resolveGeometry(
      context,
      subtitle: subtitle,
      expandedHeight: _sliverExpandedHeight,
      collapsedHeight: toolbarHeight,
      titleBuilderHeight: null,
      bottomHeight: bottomHeight,
    );
  }

  final GalleryType type;
  final String? title;
  final String? subtitle;
  final SelectedFiles selectedFiles;
  final DeviceCollection? deviceCollection;
  final bool? isDeviceFolderBackedUp;
  final Future<void> Function()? onDisableDeviceFolderBackup;
  final Collection? collection;
  final List<EnteFile>? files;

  const GalleryAppBarWidget._(
    this.type,
    this.title,
    this.selectedFiles, {
    this.subtitle,
    this.deviceCollection,
    this.isDeviceFolderBackedUp,
    this.onDisableDeviceFolderBackup,
    this.collection,
    this.files,
  });

  @override
  State<GalleryAppBarWidget> createState() => _GalleryAppBarWidgetState();
}

enum AlbumPopupAction {
  rename,
  delete,
  map,
  ownedArchive,
  sharedArchive,
  ownedHide,
  sharedHide,
  castAlbum,
  autoAddPhotos,
  sort,
  leave,
  freeUpSpace,
  disableBackup,
  setCover,
  addPhotos,
  pinAlbum,
  shareePinAlbum,
  removeLink,
  cleanUncategorized,
  downloadAlbum,
  sortByMostRecent,
  sortByMostRelevant,
  emptyTrash,
  editLocation,
  deleteLocation,
  galleryGuestView,
}

class _GalleryAppBarWidgetState extends State<GalleryAppBarWidget> {
  final _logger = Logger("GalleryAppBar");
  late StreamSubscription _userAuthEventSubscription;
  late StreamSubscription<CollectionMetaEvent> _collectionMetaEventSubscription;
  late Function() _selectedFilesListener;
  late String _appBarTitle;
  late CollectionActions collectionActions;
  bool isQuickLink = false;
  late GalleryType galleryType;

  bool _isICloudSharedAlbum = false;
  @override
  void initState() {
    super.initState();
    _selectedFilesListener = () {
      setState(() {});
    };
    collectionActions = CollectionActions(CollectionsService.instance);
    widget.selectedFiles.addListener(_selectedFilesListener);
    _userAuthEventSubscription = Bus.instance
        .on<SubscriptionPurchasedEvent>()
        .listen((event) {
          setState(() {});
        });
    _collectionMetaEventSubscription = Bus.instance
        .on<CollectionMetaEvent>()
        .where(
          (event) =>
              event.id == widget.collection?.id &&
              event.type == CollectionMetaEventType.autoAddPeople,
        )
        .listen(stateRefresh);

    _appBarTitle = widget.title ?? "";
    galleryType = widget.type;
    _checkIfICloudSharedAlbum();
  }

  Future<void> _checkIfICloudSharedAlbum() async {
    if (!Platform.isIOS ||
        widget.type != GalleryType.localFolder ||
        widget.deviceCollection == null) {
      return;
    }
    final sharedPathIDs = await FilesService.instance
        .getICloudSharedAlbumPathIDs();
    if (mounted && sharedPathIDs.contains(widget.deviceCollection!.id)) {
      setState(() {
        _isICloudSharedAlbum = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant GalleryAppBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _appBarTitle = widget.title ?? "";
    }
  }

  @override
  void dispose() {
    _userAuthEventSubscription.cancel();
    _collectionMetaEventSubscription.cancel();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    super.dispose();
  }

  void stateRefresh(dynamic event) {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    final isHierarchicalSearchable =
        inheritedSearchFilterData?.isHierarchicalSearchable ?? false;

    if (galleryType == GalleryType.homepage) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    if (!isHierarchicalSearchable) {
      return _GallerySliverAppBar(
        title: _appBarTitle,
        subtitle: widget.subtitle,
        actions: _getDefaultActions(context),
      );
    }

    return ValueListenableBuilder(
      valueListenable: inheritedSearchFilterData!
          .searchFilterDataProvider!
          .isSearchingNotifier,
      child: PreferredSize(
        preferredSize: Size.fromHeight(
          AppBarFilterChips.preferredHeight(context),
        ),
        child: const AppBarFilterChips(),
      ),
      builder: (context, isSearching, child) {
        return _GallerySliverAppBar(
          title: _appBarTitle,
          subtitle: widget.subtitle,
          actions: isSearching ? const [] : _getDefaultActions(context),
          bottom: child as PreferredSizeWidget,
        );
      },
    );
  }

  Future<dynamic> _renameAlbum(BuildContext context) async {
    if (galleryType != GalleryType.ownedCollection &&
        galleryType != GalleryType.hiddenOwnedCollection &&
        galleryType != GalleryType.quickLink) {
      showToast(
        context,
        AppLocalizations.of(
          context,
        ).typeOfGallerGallerytypeIsNotSupportedForRename(
          galleryType: "$galleryType",
        ),
      );

      return;
    }
    final result = await showTextInputDialog(
      context,
      title: isQuickLink
          ? AppLocalizations.of(context).enterAlbumName
          : AppLocalizations.of(context).renameAlbum,
      submitButtonLabel: isQuickLink
          ? AppLocalizations.of(context).done
          : AppLocalizations.of(context).rename,
      hintText: AppLocalizations.of(context).enterAlbumName,
      alwaysShowSuccessState: true,
      initialValue: widget.collection?.displayName ?? "",
      textCapitalization: TextCapitalization.words,
      onSubmit: (String text) async {
        // indicates user cancelled the rename request
        if (text == "" || text.trim() == _appBarTitle.trim()) {
          return;
        }

        try {
          await CollectionsService.instance.rename(widget.collection!, text);
          if (mounted) {
            _appBarTitle = text;
            if (isQuickLink) {
              // update the gallery type to owned collection so that correct
              // actions are shown
              galleryType = GalleryType.ownedCollection;
            }
            setState(() {});
          }
        } catch (e, s) {
          _logger.warning("Failed to rename album", e, s);
          rethrow;
        }
      },
    );
    if (result is Exception) {
      await showGenericErrorDialog(context: context, error: result);
    }
  }

  Future<dynamic> _leaveAlbum(BuildContext context) async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.critical,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: AppLocalizations.of(context).leaveAlbum,
          onTap: () async {
            await CollectionsService.instance.leaveAlbum(widget.collection!);
          },
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: AppLocalizations.of(context).cancel,
        ),
      ],
      title: AppLocalizations.of(context).leaveSharedAlbum,
      body: AppLocalizations.of(
        context,
      ).photosAddedByYouWillBeRemovedFromTheAlbum,
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

  // todo: In the new design, clicking on free up space will directly open
  // the free up space page and show loading indicator while calculating
  // the space which can be claimed up. This code duplication should be removed
  // whenever we move to the new design for free up space.
  Future<dynamic> _deleteBackedUpFiles(BuildContext context) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).calculating,
    );
    await dialog.show();
    FreeableSpaceInfo status;
    try {
      status = await FilesService.instance.getFreeableSpaceInfo(
        pathID: widget.deviceCollection!.id,
      );
    } catch (e) {
      await dialog.hide();
      unawaited(showGenericErrorDialog(context: context, error: e));
      return;
    }

    await dialog.hide();
    if (status.localIDs.isEmpty) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).allClear,
        AppLocalizations.of(context).youveNoFilesInThisAlbumThatCanBeDeleted,
      );
    } else {
      final bool? result = await routeToPage(
        context,
        FreeSpacePage(status, clearSpaceForFolder: true),
      );
      if (result == true) {
        _showSpaceFreedDialog(status);
      }
    }
  }

  void _showSpaceFreedDialog(FreeableSpaceInfo status) {
    showChoiceDialog(
      context,
      title: AppLocalizations.of(context).success,
      body: AppLocalizations.of(
        context,
      ).youHaveSuccessfullyFreedUp(storageSaved: formatBytes(status.size)),
      firstButtonLabel: AppLocalizations.of(context).rateUs,
      firstButtonOnTap: () async {
        await updateService.launchReviewUrl();
      },
      firstButtonType: ButtonType.primary,
      secondButtonLabel: AppLocalizations.of(context).ok,
      secondButtonOnTap: () async {
        if (Platform.isIOS) {
          showToast(
            context,
            AppLocalizations.of(context).remindToEmptyDeviceTrash,
          );
        }
      },
    );
  }

  List<Widget> _getDefaultActions(BuildContext context) {
    final List<Widget> actions = <Widget>[];
    // If the user has selected files, don't show any actions
    if (widget.selectedFiles.files.isNotEmpty ||
        !Configuration.instance.hasConfiguredAccount()) {
      return actions;
    }

    final strings = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);

    if (galleryType == GalleryType.magic) {
      actions.add(
        galleryAppBarPopupMenuAction<AlbumPopupAction>(
          tooltip: strings.sort,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal),
          optionsBuilder: () {
            return [
              EntePopupMenuOption(
                value: AlbumPopupAction.sortByMostRecent,
                label: strings.mostRecent,
              ),
              EntePopupMenuOption(
                value: AlbumPopupAction.sortByMostRelevant,
                label: strings.mostRelevant,
              ),
            ];
          },
          onSelected: (AlbumPopupAction value) {
            if (value == AlbumPopupAction.sortByMostRecent) {
              Bus.instance.fire(MagicSortChangeEvent(MagicSortType.mostRecent));
            } else if (value == AlbumPopupAction.sortByMostRelevant) {
              Bus.instance.fire(
                MagicSortChangeEvent(MagicSortType.mostRelevant),
              );
            }
          },
        ),
      );
    }

    final int userId = Configuration.instance.getUserID()!;
    isQuickLink = widget.collection?.isQuickLinkCollection() ?? false;
    if (galleryType.canAddFiles(widget.collection, userId)) {
      actions.add(
        IconButtonComponent(
          tooltip: strings.addFiles,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedImageAdd01),
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            await _showAddPhotoDialog(context);
          },
        ),
      );
    }

    if (galleryType.isSharable()) {
      actions.add(
        IconButtonComponent(
          tooltip: strings.share,
          icon: HugeIcon(
            icon: isQuickLink && (widget.collection!.hasLink)
                ? HugeIcons.strokeRoundedLink02
                : HugeIcons.strokeRoundedShare08,
          ),
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            await _showShareCollectionDialog();
          },
        ),
      );
    }

    final bool isArchived = widget.collection?.isArchived() ?? false;
    final bool isHidden = widget.collection?.isHidden() ?? false;

    if (!_hasOverflowMenuActions(userId, isArchived, isHidden)) {
      return actions;
    }

    actions.add(
      galleryAppBarPopupMenuAction<AlbumPopupAction>(
        tooltip: strings.more,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        optionsBuilder: () => _buildOverflowMenuOptions(
          strings: strings,
          iconColor: colorScheme.contentLight,
          userId: userId,
          isArchived: isArchived,
          isHidden: isHidden,
        ),
        onSelected: (AlbumPopupAction value) async {
          if (value == AlbumPopupAction.rename) {
            await _renameAlbum(context);
          } else if (value == AlbumPopupAction.pinAlbum) {
            await updateOrder(
              context,
              widget.collection!,
              widget.collection!.isPinned ? 0 : 1,
            );
            if (mounted) setState(() {});
          } else if (value == AlbumPopupAction.shareePinAlbum) {
            await updateShareeOrder(
              context,
              widget.collection!,
              widget.collection!.hasShareePinned() ? 0 : 1,
            );
            if (mounted) setState(() {});
          } else if (value == AlbumPopupAction.ownedArchive) {
            await archiveOrUnarchive();
          } else if (value == AlbumPopupAction.ownedHide) {
            await hideOrUnhide();
          } else if (value == AlbumPopupAction.delete) {
            await _trashCollection();
          } else if (value == AlbumPopupAction.removeLink) {
            await _removeQuickLink();
          } else if (value == AlbumPopupAction.leave) {
            await _leaveAlbum(context);
          } else if (value == AlbumPopupAction.castAlbum) {
            await showCastSheet(context, widget.collection!);
          } else if (value == AlbumPopupAction.autoAddPhotos) {
            await routeToPage(
              context,
              SmartAlbumPeople(collectionId: widget.collection!.id),
            );
            setState(() {});
          } else if (value == AlbumPopupAction.freeUpSpace) {
            await _deleteBackedUpFiles(context);
          } else if (value == AlbumPopupAction.disableBackup) {
            await widget.onDisableDeviceFolderBackup!.call();
          } else if (value == AlbumPopupAction.setCover) {
            await setCoverPhoto(context);
          } else if (value == AlbumPopupAction.sort) {
            await _showSortOption(context);
          } else if (value == AlbumPopupAction.sharedArchive) {
            final hasShareeArchived = widget.collection!.hasShareeArchived();
            final int prevVisiblity = hasShareeArchived
                ? archiveVisibility
                : visibleVisibility;
            final int newVisiblity = hasShareeArchived
                ? visibleVisibility
                : archiveVisibility;

            await changeCollectionVisibility(
              context,
              collection: widget.collection!,
              newVisibility: newVisiblity,
              prevVisibility: prevVisiblity,
              isOwner: false,
            );
            if (mounted) {
              setState(() {});
            }
          } else if (value == AlbumPopupAction.sharedHide) {
            final hasShareeHidden = widget.collection!.hasShareeHidden();
            final int prevVisiblity = hasShareeHidden
                ? hiddenVisibility
                : visibleVisibility;
            final int newVisiblity = hasShareeHidden
                ? visibleVisibility
                : hiddenVisibility;

            await changeCollectionVisibility(
              context,
              collection: widget.collection!,
              newVisibility: newVisiblity,
              prevVisibility: prevVisiblity,
              isOwner: false,
            );
            if (mounted) {
              setState(() {});
            }
          } else if (value == AlbumPopupAction.map) {
            await showOnMap();
          } else if (value == AlbumPopupAction.cleanUncategorized) {
            await onCleanUncategorizedClick(context);
          } else if (value == AlbumPopupAction.downloadAlbum) {
            await _downloadPublicAlbumToGallery(widget.files!);
          } else if (value == AlbumPopupAction.emptyTrash) {
            await emptyTrash(context);
          } else if (value == AlbumPopupAction.editLocation) {
            editLocation();
          } else if (value == AlbumPopupAction.deleteLocation) {
            await deleteLocation();
          } else if (value == AlbumPopupAction.galleryGuestView) {
            await _onGalleryGuestViewClick();
          } else {
            showToast(context, AppLocalizations.of(context).somethingWentWrong);
          }
        },
      ),
    );

    return actions;
  }

  bool _hasOverflowMenuActions(int userId, bool isArchived, bool isHidden) {
    return galleryType.canRename() ||
        galleryType.canSetCover() ||
        galleryType.showMap() ||
        galleryType.canSort() ||
        galleryType == GalleryType.uncategorized ||
        galleryType.canPin() ||
        galleryType == GalleryType.locationTag ||
        isArchived ||
        (galleryType.canArchive() && !isHidden) ||
        (!isArchived && galleryType.canHide()) ||
        widget.collection != null ||
        galleryType.canDelete() ||
        galleryType == GalleryType.trash ||
        galleryType == GalleryType.sharedCollection ||
        (galleryType == GalleryType.localFolder && !_isICloudSharedAlbum) ||
        _canDisableDeviceFolderBackup ||
        (galleryType == GalleryType.sharedPublicCollection &&
            (widget.collection?.isDownloadEnabledForPublicLink() ?? false));
  }

  Future<List<EntePopupMenuOption<AlbumPopupAction>>>
  _buildOverflowMenuOptions({
    required AppLocalizations strings,
    required Color iconColor,
    required int userId,
    required bool isArchived,
    required bool isHidden,
  }) async {
    final warningColor = context.componentColors.warning;
    final canAutoAdd =
        hasGrantedMLConsent && (widget.collection?.canAutoAdd(userId) ?? false);
    final hasAutoAddPeople = canAutoAdd
        ? !((await smartAlbumsService.getSmartConfigs())[widget.collection!.id]
                  ?.personIDs
                  .isEmpty ??
              true)
        : false;

    return [
      if (galleryType.canRename())
        _menuOption(
          AlbumPopupAction.rename,
          isQuickLink ? strings.convertToAlbum : strings.renameAlbum,
          galleryAppBarMenuIcon(
            isQuickLink
                ? HugeIcons.strokeRoundedAlbum02
                : HugeIcons.strokeRoundedPencilEdit01,
            iconColor,
          ),
        ),
      if (galleryType.canSetCover())
        _menuOption(
          AlbumPopupAction.setCover,
          strings.setCover,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedImage01, iconColor),
        ),
      if (galleryType.showMap())
        _menuOption(
          AlbumPopupAction.map,
          strings.map,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedLocation01, iconColor),
        ),
      if (galleryType.canSort())
        _menuOption(
          AlbumPopupAction.sort,
          strings.sortAlbumsBy,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedSorting01, iconColor),
        ),
      if (galleryType == GalleryType.uncategorized)
        _menuOption(
          AlbumPopupAction.cleanUncategorized,
          strings.cleanUncategorized,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedClean, iconColor),
        ),
      if (galleryType.canPin())
        _menuOption(
          AlbumPopupAction.pinAlbum,
          widget.collection!.isPinned ? strings.unpin : strings.pin,
          galleryAppBarMenuIcon(
            widget.collection!.isPinned
                ? HugeIcons.strokeRoundedPinOff
                : HugeIcons.strokeRoundedPin,
            iconColor,
          ),
        ),
      if (galleryType == GalleryType.locationTag)
        _menuOption(
          AlbumPopupAction.editLocation,
          strings.editLocation,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedLocation01, iconColor),
        ),
      if (galleryType == GalleryType.locationTag)
        _menuOption(
          AlbumPopupAction.deleteLocation,
          strings.deleteLocation,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedDelete01, warningColor),
          labelColor: warningColor,
        ),
      if (isArchived || (galleryType.canArchive() && !isHidden))
        _menuOption(
          AlbumPopupAction.ownedArchive,
          isArchived ? strings.unarchiveAlbum : strings.archiveAlbum,
          galleryAppBarMenuIcon(
            isArchived
                ? HugeIcons.strokeRoundedUnarchive03
                : HugeIcons.strokeRoundedArchive03,
            iconColor,
          ),
        ),
      if (!isArchived && galleryType.canHide())
        _menuOption(
          AlbumPopupAction.ownedHide,
          isHidden ? strings.unhide : strings.hide,
          galleryAppBarMenuIcon(
            isHidden
                ? HugeIcons.strokeRoundedView
                : HugeIcons.strokeRoundedViewOffSlash,
            iconColor,
          ),
        ),
      if (widget.collection != null)
        _menuOption(
          AlbumPopupAction.galleryGuestView,
          strings.guestView,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedIncognito, iconColor),
        ),
      if (widget.collection != null && castService.isSupported)
        _menuOption(
          AlbumPopupAction.castAlbum,
          strings.castAlbum,
          galleryAppBarMenuIcon(
            !flagService.enableMultiCast &&
                    castService.getActiveSessions().isNotEmpty
                ? HugeIcons.strokeRoundedTvSmart
                : HugeIcons.strokeRoundedTv02,
            iconColor,
          ),
        ),
      if (canAutoAdd)
        _menuOption(
          AlbumPopupAction.autoAddPhotos,
          hasAutoAddPeople ? strings.editAutoAddPeople : strings.autoAddPeople,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedUserAdd01, iconColor),
        ),
      if (galleryType.canDelete())
        _menuOption(
          isQuickLink ? AlbumPopupAction.removeLink : AlbumPopupAction.delete,
          isQuickLink ? strings.removeLink : strings.deleteAlbum,
          galleryAppBarMenuIcon(
            isQuickLink
                ? HugeIcons.strokeRoundedLinkBackward
                : HugeIcons.strokeRoundedDelete01,
            iconColor,
          ),
        ),
      if (galleryType == GalleryType.sharedCollection)
        _menuOption(
          AlbumPopupAction.shareePinAlbum,
          widget.collection!.hasShareePinned() ? strings.unpin : strings.pin,
          galleryAppBarMenuIcon(
            widget.collection!.hasShareePinned()
                ? HugeIcons.strokeRoundedPinOff
                : HugeIcons.strokeRoundedPin,
            iconColor,
          ),
        ),
      if (galleryType == GalleryType.sharedCollection)
        _menuOption(
          AlbumPopupAction.sharedArchive,
          widget.collection!.hasShareeArchived()
              ? strings.unarchiveAlbum
              : strings.archiveAlbum,
          galleryAppBarMenuIcon(
            widget.collection!.hasShareeArchived()
                ? HugeIcons.strokeRoundedUnarchive03
                : HugeIcons.strokeRoundedArchive03,
            iconColor,
          ),
        ),
      if (galleryType == GalleryType.sharedCollection)
        _menuOption(
          AlbumPopupAction.sharedHide,
          widget.collection!.hasShareeHidden() ? strings.unhide : strings.hide,
          galleryAppBarMenuIcon(
            widget.collection!.hasShareeHidden()
                ? HugeIcons.strokeRoundedView
                : HugeIcons.strokeRoundedViewOffSlash,
            iconColor,
          ),
        ),
      if (galleryType == GalleryType.sharedCollection)
        _menuOption(
          AlbumPopupAction.leave,
          strings.leaveAlbum,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedLogout05, iconColor),
        ),
      if (galleryType == GalleryType.localFolder && !_isICloudSharedAlbum)
        _menuOption(
          AlbumPopupAction.freeUpSpace,
          strings.freeUpSpace,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedClean, iconColor),
        ),
      if (_canDisableDeviceFolderBackup)
        _menuOption(
          AlbumPopupAction.disableBackup,
          strings.disableBackup,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedUpload01, iconColor),
        ),
      if (galleryType == GalleryType.sharedPublicCollection &&
          (widget.collection?.isDownloadEnabledForPublicLink() ?? false))
        _menuOption(
          AlbumPopupAction.downloadAlbum,
          strings.download,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedDownload01, iconColor),
        ),
      if (galleryType == GalleryType.trash)
        _menuOption(
          AlbumPopupAction.emptyTrash,
          strings.deleteAll,
          galleryAppBarMenuIcon(HugeIcons.strokeRoundedDelete01, warningColor),
          labelColor: warningColor,
        ),
    ];
  }

  bool get _isDeviceFolderBackedUp =>
      widget.isDeviceFolderBackedUp ??
      widget.deviceCollection?.shouldBackup ??
      false;

  bool get _canDisableDeviceFolderBackup =>
      galleryType == GalleryType.localFolder &&
      _isDeviceFolderBackedUp &&
      widget.onDisableDeviceFolderBackup != null;

  EntePopupMenuOption<AlbumPopupAction> _menuOption(
    AlbumPopupAction value,
    String label,
    Widget leadingWidget, {
    Color? labelColor,
  }) {
    return EntePopupMenuOption(
      value: value,
      label: label,
      labelColor: labelColor,
      leadingWidget: leadingWidget,
    );
  }

  Future<void> _downloadPublicAlbumToGallery(List<EnteFile>? files) async {
    if (files == null || files.isEmpty) {
      return;
    }
    if (flagService.internalUser) {
      try {
        await galleryDownloadQueueService.enqueueFiles(
          files,
          persistToFilesDB: false,
        );
      } catch (e, s) {
        _logger.severe("Failed to download album", e, s);
        await showGenericErrorDialog(context: context, error: e);
      }
      return;
    }

    final totalFiles = files.length;
    final dialog = createProgressDialog(
      context,
      "Downloading... 0/$totalFiles",
      isDismissible: false,
    );
    await dialog.show();

    try {
      for (var i = 0; i < files.length; i++) {
        await downloadToGallery(files[i], persistToFilesDB: false);
        dialog.update(message: "Downloading... ${i + 1}/$totalFiles");
      }
    } catch (e, s) {
      _logger.severe("Failed to download album", e, s);
      await showGenericErrorDialog(context: context, error: e);
    }
    await dialog.hide();
  }

  void editLocation() {
    showEditLocationSheet(
      context,
      InheritedLocationScreenState.of(context).locationTagEntity,
    );
  }

  Future<void> deleteLocation() async {
    try {
      await locationService.deleteLocationTag(
        InheritedLocationScreenState.of(context).locationTagEntity.id,
      );
      Navigator.of(context).pop();
    } catch (e) {
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> onCleanUncategorizedClick(BuildContext buildContext) async {
    final actionResult = await showChoiceActionSheet(
      context,
      isCritical: true,
      title: AppLocalizations.of(context).cleanUncategorized,
      firstButtonLabel: AppLocalizations.of(context).confirm,
      body: AppLocalizations.of(context).cleanUncategorizedDescription,
    );
    if (actionResult?.action != null && mounted) {
      if (actionResult!.action == ButtonAction.first) {
        await collectionActions.removeFromUncatIfPresentInOtherAlbum(
          widget.collection!,
          buildContext,
        );
      }
    }
  }

  Future<void> setCoverPhoto(BuildContext context) async {
    final int? coverPhotoID = await showPickCoverPhotoSheet(
      context,
      widget.collection!,
    );
    if (coverPhotoID != null) {
      unawaited(changeCoverPhoto(context, widget.collection!, coverPhotoID));
    }
  }

  Future<void> showOnMap() async {
    if (!mapEnabled) {
      try {
        await setMapEnabled(true);
      } catch (e) {
        showShortToast(
          context,
          AppLocalizations.of(context).somethingWentWrong,
        );
        return;
      }
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MapScreen(
            filesFutureFn: () async {
              return FilesDB.instance.getAllFilesCollection(
                widget.collection!.id,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showSortOption(BuildContext bContext) async {
    final bool? sortByAsc = await showMenu<bool>(
      context: bContext,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width,
        kToolbarHeight + 12,
        12,
        0,
      ),
      items: [
        PopupMenuItem(
          value: false,
          child: Text(AppLocalizations.of(context).sortNewestFirst),
        ),
        PopupMenuItem(
          value: true,
          child: Text(AppLocalizations.of(context).sortOldestFirst),
        ),
      ],
    );
    if (sortByAsc != null) {
      unawaited(changeSortOrder(bContext, widget.collection!, sortByAsc));
    }
  }

  Future<void> _trashCollection() async {
    // Fetch the count by-passing the cache to avoid any stale data
    final int count = await CollectionsService.instance.getFileCount(
      widget.collection!,
      useCache: false,
    );
    final bool isEmptyCollection = count == 0;
    if (isEmptyCollection) {
      final dialog = createProgressDialog(
        context,
        AppLocalizations.of(context).pleaseWaitDeletingAlbum,
      );
      await dialog.show();
      try {
        await CollectionsService.instance.trashEmptyCollection(
          widget.collection!,
        );
        await dialog.hide();
        Navigator.of(context).pop();
      } catch (e, s) {
        _logger.warning("failed to trash collection", e, s);
        await dialog.hide();
        await showGenericErrorDialog(context: context, error: e);
      }
    } else {
      final bool result = await collectionActions.deleteCollectionSheet(
        context,
        widget.collection!,
      );
      if (result == true) {
        Navigator.of(context).pop();
      } else {
        debugPrint("No pop");
      }
    }
  }

  Future<void> _removeQuickLink() async {
    try {
      final bool result = await CollectionActions(
        CollectionsService.instance,
      ).disableUrl(context, widget.collection!);
      if (result && mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      _logger.severe("failed to trash collection", e, s);
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _showShareCollectionDialog() async {
    final collection = widget.collection;
    try {
      if (collection == null ||
          (galleryType != GalleryType.ownedCollection &&
              galleryType != GalleryType.sharedCollection &&
              galleryType != GalleryType.hiddenOwnedCollection &&
              galleryType != GalleryType.favorite &&
              !isQuickLink)) {
        throw Exception("Cannot share collection of type $galleryType");
      }
      final int? userID = Configuration.instance.getUserID();
      final bool isOwner = userID == collection.owner.id;
      final CollectionParticipantRole role = collection.getRole(userID ?? -1);
      final bool isAdmin = role == CollectionParticipantRole.admin;
      final bool canManageParticipants = isOwner || isAdmin;
      if (canManageParticipants) {
        final bool shouldOpenManageLink =
            isOwner && isQuickLink && collection.hasLink;
        unawaited(
          routeToPage(
            context,
            shouldOpenManageLink
                ? ManageSharedLinkWidget(collection: collection)
                : ShareCollectionPage(collection),
          ),
        );
      } else if (collection.hasLink) {
        unawaited(routeToPage(context, ShareCollectionPage(collection)));
      } else {
        unawaited(routeToPage(context, AlbumParticipantsPage(collection)));
      }
    } catch (e, s) {
      _logger.severe("Failed to open share collection dialog", e, s);
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _showAddPhotoDialog(BuildContext bContext) async {
    final collection = widget.collection;
    try {
      if (galleryType == GalleryType.sharedPublicCollection &&
          collection!.isCollectEnabledForPublicLink()) {
        final authToken = CollectionsService.instance.getSharedPublicAlbumToken(
          collection.id,
        );
        final albumKey = CollectionsService.instance.getSharedPublicAlbumKey(
          collection.id,
        );

        final res = await showChoiceDialog(
          context,
          title: AppLocalizations.of(context).openAlbumInBrowserTitle,
          firstButtonLabel: AppLocalizations.of(context).openAlbumInBrowser,
          secondButtonLabel: AppLocalizations.of(context).cancel,
          firstButtonType: ButtonType.primary,
        );

        if (res != null && res.action == ButtonAction.first) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WebPage(
                widget.title ?? "",
                "https://albums.ente.com/?t=$authToken#$albumKey",
              ),
            ),
          );
        }
      } else {
        await showAddPhotosSheet(bContext, collection!);
      }
    } catch (e, s) {
      _logger.severe("Failed to show add photo dialog", e, s);
      await showGenericErrorDialog(context: bContext, error: e);
    }
  }

  Future<void> hideOrUnhide() async {
    final isHidden = widget.collection!.isHidden();
    final int prevVisiblity = isHidden ? hiddenVisibility : visibleVisibility;
    final int newVisiblity = isHidden ? visibleVisibility : hiddenVisibility;

    await changeCollectionVisibility(
      context,
      collection: widget.collection!,
      newVisibility: newVisiblity,
      prevVisibility: prevVisiblity,
    );
    setState(() {});
  }

  Future<void> archiveOrUnarchive() async {
    final isArchived = widget.collection!.isArchived();
    final int prevVisiblity = isArchived
        ? archiveVisibility
        : visibleVisibility;
    final int newVisiblity = isArchived ? visibleVisibility : archiveVisibility;

    await changeCollectionVisibility(
      context,
      collection: widget.collection!,
      newVisibility: newVisiblity,
      prevVisibility: prevVisiblity,
    );
    setState(() {});
  }

  Future<void> _onGalleryGuestViewClick() async {
    if (await LocalAuthentication().isDeviceSupported()) {
      // Get all files from the collection with proper sort order
      late final List<EnteFile> collectionFiles;
      if (widget.files != null) {
        // If files are already provided, use them
        collectionFiles = widget.files!;
      } else if (widget.collection != null) {
        // Fetch all files from the collection
        final filesResult = await FilesDB.instance.getFilesInCollection(
          widget.collection!.id,
          galleryLoadStartTime,
          galleryLoadEndTime,
          asc: widget.collection!.pubMagicMetadata.asc ?? false,
        );
        collectionFiles = filesResult.files;
      } else {
        showToast(context, AppLocalizations.of(context).somethingWentWrong);
        return;
      }

      if (collectionFiles.isEmpty) {
        showToast(context, AppLocalizations.of(context).nothingToSeeHere);
        return;
      }

      // Use the same logic as selected files guest view
      final page = DetailPage(
        DetailPageConfiguration(
          collectionFiles,
          0,
          "guest_view",
          galleryType: galleryType,
        ),
      );
      await localSettings.setOnGuestView(true);
      routeToPage(context, page, forceCustomPageRoute: true).ignore();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Bus.instance.fire(GuestViewEvent(true, false));
      });
    } else {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).noSystemLockFound,
        AppLocalizations.of(context).guestViewEnablePreSteps,
      );
    }
  }
}

class _GallerySliverAppBar extends StatelessWidget {
  const _GallerySliverAppBar({
    required this.title,
    this.subtitle,
    required this.actions,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return SliverAppBarComponent(
      title: title,
      subtitle: subtitle,
      actions: actions,
      bottom: bottom,
      expandedHeight: GalleryAppBarWidget._sliverExpandedHeight,
      collapsedHeight: GalleryAppBarWidget.toolbarHeight,
      backgroundColor: GalleryAppBarWidget.backgroundColor(context),
    );
  }
}
