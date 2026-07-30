import "dart:async";
import 'dart:io';

import "package:ente_components/ente_components.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:local_auth/local_auth.dart";
import 'package:logging/logging.dart';
import 'package:media_extension/media_extension.dart';
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/download/gallery.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/hidden_service.dart';
import "package:photos/services/video_preview_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import 'package:photos/ui/collections/collection_action_sheet.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/viewer/actions/suggest_delete_sheet.dart';
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file_details/favorite_widget.dart";
import "package:photos/ui/viewer/file_details/upload_icon_widget.dart";
import 'package:photos/utils/dialog_util.dart';
import "package:photos/utils/magic_util.dart";
import "package:photos/utils/share_util.dart";

class FileAppBar extends StatefulWidget {
  final EnteFile file;
  final Function(EnteFile) onFileRemoved;
  final Function(EnteFile) onEditRequested;
  final ValueNotifier<bool> enableFullScreenNotifier;
  final GalleryType? galleryType;
  final DetailPageMode mode;
  final bool showEditAction;
  final FutureOr<void> Function(BuildContext context)? onBackPressed;

  const FileAppBar(
    this.file,
    this.onFileRemoved,
    this.onEditRequested, {
    required this.enableFullScreenNotifier,
    this.galleryType,
    this.mode = DetailPageMode.full,
    this.showEditAction = true,
    this.onBackPressed,
    super.key,
  });

  @override
  FileAppBarState createState() => FileAppBarState();
}

class FileAppBarState extends State<FileAppBar> {
  final _logger = Logger("FadingAppBar");
  final List<Widget> _actions = [];
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  bool isGuestView = false;
  bool shouldLoopVideo = localSettings.shouldLoopVideo();
  bool _reloadActions = false;
  ValueNotifier<String?>? _showingThumbnailFallbackNotifier;

  @override
  void didUpdateWidget(FileAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (detailPageFileIdentifier(oldWidget.file) !=
            detailPageFileIdentifier(widget.file) ||
        oldWidget.showEditAction != widget.showEditAction) {
      _getActions();
    }
  }

  @override
  void initState() {
    super.initState();
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      setState(() {
        isGuestView = event.isGuestView;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final detailPageState = InheritedDetailPageState.maybeOf(context);
    _updateShowingThumbnailFallbackNotifier(
      detailPageState?.showingThumbnailFallbackNotifier,
    );
  }

  void _onThumbnailFallbackChanged() {
    _requestActionsReload();
  }

  void _updateShowingThumbnailFallbackNotifier(
    ValueNotifier<String?>? notifier,
  ) {
    if (_showingThumbnailFallbackNotifier == notifier) {
      return;
    }
    _showingThumbnailFallbackNotifier?.removeListener(
      _onThumbnailFallbackChanged,
    );
    _showingThumbnailFallbackNotifier = notifier;
    _showingThumbnailFallbackNotifier?.addListener(_onThumbnailFallbackChanged);
  }

  @override
  void dispose() {
    _showingThumbnailFallbackNotifier?.removeListener(
      _onThumbnailFallbackChanged,
    );
    _guestViewEventSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("building app bar ${widget.file.generatedID?.toString()}");

    //When the widget is initialized, the actions are not available.
    //Cannot call _getActions() in initState.
    if (_actions.isEmpty || _reloadActions) {
      _getActions();
      _reloadActions = false;
    }
    final shouldShowActions = !isGuestView;
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder(
        valueListenable: widget.enableFullScreenNotifier,
        builder: (context, bool isFullScreen, child) {
          return IgnorePointer(
            ignoring: isFullScreen,
            child: AnimatedOpacity(
              opacity: isFullScreen ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.6),
                Colors.transparent,
              ],
              stops: const [0, 0.2, 1],
            ),
          ),
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: AppBar(
                clipBehavior: Clip.none,
                key: ValueKey(isGuestView),
                iconTheme: const IconThemeData(
                  color: Colors.white,
                ), //same for both themes
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    final onBackPressed = widget.onBackPressed;
                    if (onBackPressed != null && !isGuestView) {
                      unawaited(Future.sync(() => onBackPressed(context)));
                      return;
                    }
                    isGuestView
                        ? _requestAuthentication()
                        : Navigator.of(context).pop();
                  },
                ),
                actions: shouldShowActions ? _actions : [],
                elevation: 0,
                backgroundColor: const Color(0x00000000),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _requestActionsReload() {
    if (mounted) {
      setState(() {
        _reloadActions = true;
      });
    }
  }

  List<Widget> _getActions() {
    _actions.clear();

    // Show info icon when thumbnail fallback is active for THIS file
    final fallbackFileId = InheritedDetailPageState.maybeOf(
      context,
    )?.showingThumbnailFallbackNotifier.value;
    final currentFileId = detailPageFileIdentifier(widget.file);
    final showingFallback =
        fallbackFileId != null && fallbackFileId == currentFileId;
    if (showingFallback) {
      _actions.add(
        Tooltip(
          message:
              "Your device doesn't support this image format. Showing a preview instead.",
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: backgroundElevated2Dark,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 14),
          preferBelow: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Icon(Icons.info_outline),
            ),
          ),
        ),
      );
    }

    final bool isOwnedByUser = widget.file.isOwner;
    final bool isFileUploaded = widget.file.isUploaded;
    final int? collectionID = widget.file.collectionID;
    final Collection? collection = collectionID != null
        ? CollectionsService.instance.getCollectionByID(collectionID)
        : null;
    bool isFileHidden = false;
    if (isOwnedByUser && isFileUploaded) {
      isFileHidden = collection?.isHidden() ?? false;
    }
    final bool canSuggestDeleteAction = canSuggestDeleteForFile(
      file: widget.file,
      collection: collection,
    );
    if (widget.file.isLiveOrMotionPhoto) {
      _actions.add(
        IconButton(
          icon: const Icon(Icons.album_outlined),
          onPressed: () {
            showShortToast(
              context,
              AppLocalizations.of(context).pressAndHoldToPlayVideoDetailed,
            );
          },
        ),
      );
    }
    if (!isFileHidden && isFileUploaded && widget.file is! TrashFile) {
      _actions.add(Center(child: FavoriteWidget(widget.file)));
    }
    if (!isFileUploaded && !isLocalGalleryMode) {
      _actions.add(
        UploadIconWidget(file: widget.file, key: ValueKey(widget.file.tag)),
      );
    }

    final List<EntePopupMenuOption<int>> items = [];
    final bool restrictFileActions =
        widget.mode == DetailPageMode.minimalistic || widget.file is TrashFile;

    if (restrictFileActions) {
      items.add(
        _fileMenuOption(
          AppLocalizations.of(context).info,
          value: 12,
          hugeIcon: HugeIcons.strokeRoundedInformationCircle,
        ),
      );
    } else {
      if (isFileUploaded) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).download,
            value: 1,
            hugeIcon: HugeIcons.strokeRoundedDownload01,
          ),
        );
        if (isOwnedByUser && !isFileHidden) {
          items.add(
            _fileMenuOption(
              AppLocalizations.of(context).sendLink,
              value: 14,
              hugeIcon: HugeIcons.strokeRoundedNavigation03,
            ),
          );
        }
      }
      // Edit option for images, live photos, and videos
      if (widget.showEditAction &&
          (widget.file.fileType == FileType.image ||
              widget.file.fileType == FileType.livePhoto ||
              widget.file.fileType == FileType.video)) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).edit,
            value: 11,
            hugeIcon: HugeIcons.strokeRoundedSlidersHorizontal,
          ),
        );
      }
      // options for files owned by the user
      if (isOwnedByUser && !isFileHidden && isFileUploaded) {
        final bool isArchived =
            widget.file.magicMetadata.visibility == archiveVisibility;
        items.add(
          _fileMenuOption(
            isArchived
                ? AppLocalizations.of(context).unarchive
                : AppLocalizations.of(context).archive,
            value: 2,
            hugeIcon: isArchived
                ? HugeIcons.strokeRoundedUnarchive03
                : HugeIcons.strokeRoundedArchive03,
          ),
        );
      }

      if ((widget.file.fileType == FileType.image ||
              widget.file.fileType == FileType.livePhoto) &&
          Platform.isAndroid) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).setAs,
            value: 3,
            hugeIcon: HugeIcons.strokeRoundedImage01,
          ),
        );
      }
      if (isOwnedByUser && widget.file.isUploaded) {
        if (!isFileHidden) {
          items.add(
            _fileMenuOption(
              AppLocalizations.of(context).hide,
              value: 4,
              hugeIcon: HugeIcons.strokeRoundedViewOffSlash,
            ),
          );
        } else {
          items.add(
            _fileMenuOption(
              AppLocalizations.of(context).unhide,
              value: 5,
              hugeIcon: HugeIcons.strokeRoundedView,
            ),
          );
        }
      }

      items.add(
        _fileMenuOption(
          AppLocalizations.of(context).guestView,
          value: 6,
          hugeIcon: HugeIcons.strokeRoundedIncognito,
        ),
      );

      if (canSuggestDeleteAction) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).suggestDeletion,
            value: 13,
            hugeIcon: HugeIcons.strokeRoundedFlag01,
          ),
        );
      }

      items.add(
        _fileMenuOption(
          AppLocalizations.of(context).info,
          value: 12,
          hugeIcon: HugeIcons.strokeRoundedInformationCircle,
        ),
      );
    }

    if (widget.file.isVideo && !restrictFileActions) {
      // Video streaming options
      if (_shouldShowCreateStreamOption()) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).createStream,
            value: 8,
            hugeIcon: HugeIcons.strokeRoundedVideoReplay,
          ),
        );
      }

      if (_shouldShowRecreateStreamOption()) {
        items.add(
          _fileMenuOption(
            AppLocalizations.of(context).recreateStream,
            value: 9,
            hugeIcon: HugeIcons.strokeRoundedRefresh,
          ),
        );
      }

      items.add(
        _fileMenuOption(
          shouldLoopVideo
              ? AppLocalizations.of(context).loopVideoOn
              : AppLocalizations.of(context).loopVideoOff,
          value: 7,
          hugeIcon: shouldLoopVideo
              ? HugeIcons.strokeRoundedRepeatOff
              : HugeIcons.strokeRoundedRepeat,
        ),
      );
    }

    if (items.isNotEmpty) {
      _actions.add(
        EntePopupMenuButton<int>(
          optionsBuilder: () => items,
          onSelected: (selected) async {
            if (!mounted) {
              return;
            }
            await _handleFileMenuSelection(selected, collection);
          },
          child: Tooltip(
            message: MaterialLocalizations.of(context).moreButtonTooltip,
            child: const SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMoreVertical,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _actions;
  }

  EntePopupMenuOption<int> _fileMenuOption(
    String label, {
    required int value,
    required List<List<dynamic>> hugeIcon,
  }) {
    return EntePopupMenuOption<int>(
      value: value,
      label: label,
      leadingWidget: HugeIcon(
        icon: hugeIcon,
        size: IconSizes.small,
        color: context.componentColors.textLight,
      ),
    );
  }

  Future<void> _handleFileMenuSelection(
    int value,
    Collection? collection,
  ) async {
    if (value == 1) {
      await _download(widget.file);
    } else if (value == 14) {
      await _sendLink(widget.file);
    } else if (value == 2) {
      await _toggleFileArchiveStatus(widget.file);
    } else if (value == 3) {
      await _setAs(widget.file);
    } else if (value == 4) {
      await _handleHideRequest(context);
    } else if (value == 5) {
      await _handleUnHideRequest(context);
    } else if (value == 6) {
      await _onTapGuestView();
    } else if (value == 99) {
      try {
        await VideoPreviewService.instance.chunkAndUploadVideo(
          context,
          widget.file,
        );
      } catch (e) {
        if (mounted) {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
    } else if (value == 7) {
      _onToggleLoopVideo();
    } else if (value == 8) {
      await _handleVideoStream('create');
    } else if (value == 9) {
      await _handleVideoStream('recreate');
    } else if (value == 11) {
      widget.onEditRequested(widget.file);
    } else if (value == 12) {
      await showDetailsSheet(context, widget.file);
    } else if (value == 13) {
      if (collection != null) {
        await _handleSuggestDelete(collection);
      }
    }
  }

  Future<void> _handleSuggestDelete(Collection collection) async {
    if (widget.file.uploadedFileID == null) {
      return;
    }
    await showSuggestDeleteSheet(
      context: context,
      onConfirm: () async {
        await CollectionsService.instance.suggestDeleteFromCollection(
          collection.id,
          [widget.file],
        );
        widget.onFileRemoved(widget.file);
      },
    );
  }

  void _onToggleLoopVideo() {
    localSettings.setShouldLoopVideo(!shouldLoopVideo);
    setState(() {
      _reloadActions = true;
      shouldLoopVideo = !shouldLoopVideo;
    });
  }

  Future<void> _handleHideRequest(BuildContext context) async {
    try {
      final hideResult = await CollectionsService.instance.hideFiles(context, [
        widget.file,
      ]);
      if (hideResult) {
        widget.onFileRemoved(widget.file);
      }
    } catch (e, s) {
      _logger.severe("failed to update file visibility", e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _handleUnHideRequest(BuildContext context) async {
    final selectedFiles = SelectedFiles();
    selectedFiles.files.add(widget.file);
    await showCollectionActionSheet(
      context,
      selectedFiles: selectedFiles,
      actionType: CollectionActionType.unHide,
    );
  }

  Future<void> _toggleFileArchiveStatus(EnteFile file) async {
    final bool isArchived =
        widget.file.magicMetadata.visibility == archiveVisibility;
    await changeVisibility(context, [
      widget.file,
    ], isArchived ? visibleVisibility : archiveVisibility);
    if (mounted) {
      setState(() {
        _reloadActions = true;
      });
    }
  }

  Future<void> _download(EnteFile file) async {
    final existingFolderName =
        await getExistingLocalFolderNameForDownloadSkipToast(file);
    if (existingFolderName != null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showToast(
          context,
          l10n.downloadSkippedAlreadyAvailableOnDevice(
            fileName: getDownloadSkipToastFileName(file),
            albumName: existingFolderName,
          ),
          iosLongToastLengthInSec: 4,
        );
      }
      return;
    }

    final fileToDownload = !file.isRemoteOnlyFile
        ? (file.copyWith()..localID = null)
        : file;
    final persistToFilesDB =
        widget.galleryType != GalleryType.sharedPublicCollection;
    if (flagService.internalUser) {
      try {
        await galleryDownloadQueueService.enqueueFiles([
          fileToDownload,
        ], persistToFilesDB: persistToFilesDB);
      } catch (e) {
        _logger.warning("Failed to save file", e);
        if (mounted) {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
      return;
    }

    if (!mounted) return;
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).downloading,
      isDismissible: true,
    );
    await dialog.show();
    try {
      await downloadToGallery(
        fileToDownload,
        persistToFilesDB: persistToFilesDB,
      );
      if (!mounted) {
        await dialog.hide();
        return;
      }
      showToast(context, AppLocalizations.of(context).fileSavedToGallery);
      await dialog.hide();
    } catch (e) {
      _logger.warning("Failed to save file", e);
      await dialog.hide();
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _sendLink(EnteFile file) async {
    if (!file.isUploaded || !file.isOwner) {
      showShortToast(
        context,
        AppLocalizations.of(context).canOnlyCreateLinkForFilesOwnedByYou,
      );
      return;
    }
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).creatingLink,
      isDismissible: true,
    );
    await dialog.show();
    if (!mounted) return;
    final Collection? sharedLinkCollection = await CollectionActions(
      CollectionsService.instance,
    ).createSharedCollectionLink(context, [file]);
    if (!mounted) {
      await dialog.hide();
      return;
    }
    if (sharedLinkCollection == null) {
      await dialog.hide();
      return;
    }
    final String url = CollectionsService.instance.getPublicUrl(
      sharedLinkCollection,
    );
    await dialog.hide();
    unawaited(Clipboard.setData(ClipboardData(text: url)));
    if (!mounted) return;
    await shareLinkWithDescription(url, context: context);
  }

  Future<void> _setAs(EnteFile file) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      final File? fileToSave = await (getFile(file));
      if (fileToSave == null) {
        throw Exception("Fail to get file for setAs operation");
      }
      final m = MediaExtension();
      final bool result = await m.setAs("file://${fileToSave.path}", "image/*");
      if (result == false) {
        if (!mounted) return;
        showShortToast(
          context,
          AppLocalizations.of(context).somethingWentWrong,
        );
      }
      await dialog.hide();
    } catch (e) {
      await dialog.hide();
      _logger.severe("Failed to use as", e);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onTapGuestView() async {
    if (await LocalAuthentication().isDeviceSupported()) {
      Bus.instance.fire(GuestViewEvent(true, true));
      await localSettings.setOnGuestView(true);
    } else {
      if (!mounted) return;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).noSystemLockFound,
        AppLocalizations.of(context).guestViewEnablePreSteps,
      );
    }
  }

  Future<void> _requestAuthentication() async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          "Please authenticate to view more photos and videos.",
        );
    if (hasAuthenticated) {
      Bus.instance.fire(GuestViewEvent(false, false));
      await localSettings.setOnGuestView(false);
    }
  }

  bool _shouldShowCreateStreamOption() {
    // Show "Create Stream" option for uploaded video files without streams
    return _ensureBasicRequirements() &&
        !fileDataService.previewIds.containsKey(widget.file.uploadedFileID!);
  }

  bool _shouldShowRecreateStreamOption() {
    // Show "Recreate Stream" option for uploaded video files with existing streams
    return _ensureBasicRequirements() &&
        fileDataService.previewIds.containsKey(widget.file.uploadedFileID!);
  }

  bool _ensureBasicRequirements() {
    // Skip if sv=1 (server indicates streaming not needed)
    final userId = Configuration.instance.getUserID();
    return widget.file.fileType == FileType.video &&
        widget.file.isUploaded &&
        widget.file.fileSize != null &&
        (widget.file.pubMagicMetadata?.sv ?? 0) != 1 &&
        widget.file.ownerID == userId &&
        VideoPreviewService.instance.isVideoStreamingEnabled;
  }

  Future<void> _handleVideoStream(String streamType) async {
    try {
      final bool wasAdded = await VideoPreviewService.instance.addToManualQueue(
        widget.file,
        streamType,
      );

      if (!wasAdded) {
        // File was already in queue
        if (!mounted) return;
        showToast(context, AppLocalizations.of(context).videoAlreadyInQueue);
        return;
      }

      if (!mounted) return;
      showToast(context, AppLocalizations.of(context).addedToQueue);

      if (mounted) {
        setState(() {
          _reloadActions = true;
        });
      }
    } catch (e, s) {
      _logger.severe("Failed to $streamType video stream", e, s);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }
}
