import "dart:async";
import "dart:io";

import "package:collection/collection.dart";
import "package:ente_icons/ente_icons.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/social/comments_screen.dart";
import "package:photos/ui/social/like_collection_selector_sheet.dart";
import "package:photos/ui/social/likes_bottom_sheet.dart";
import "package:photos/ui/viewer/actions/suggest_delete_sheet.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/panorama_util.dart";
import "package:photos/utils/share_util.dart";

final _logger = Logger("FileBottomBar");

class FileBottomBar extends StatefulWidget {
  final EnteFile file;
  final Function(EnteFile) onFileRemoved;
  final int? userID;
  final ValueNotifier<bool> enableFullScreenNotifier;
  final bool isLocalOnlyContext;

  const FileBottomBar(
    this.file, {
    required this.onFileRemoved,
    required this.enableFullScreenNotifier,
    this.userID,
    this.isLocalOnlyContext = false,
    super.key,
  });

  @override
  FileBottomBarState createState() => FileBottomBarState();
}

class FileBottomBarState extends State<FileBottomBar> {
  final GlobalKey shareButtonKey = GlobalKey();
  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  int? lastFileGenID;
  bool _hasLiked = false;
  int _commentCount = 0;

  @override
  void initState() {
    super.initState();
    _updateSocialState();
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      setState(() {
        isGuestView = event.isGuestView;
      });
    });
  }

  @override
  void didUpdateWidget(FileBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.uploadedFileID != widget.file.uploadedFileID) {
      _updateSocialState();
    }
  }

  Future<void> _updateSocialState({bool sync = false}) async {
    if (widget.file.uploadedFileID == null) {
      _hasLiked = false;
      _commentCount = 0;
      return;
    }

    final fileID = widget.file.uploadedFileID!;
    final collectionID = widget.file.collectionID;
    final provider = SocialDataProvider.instance;

    // Sync from server if requested and we have a collection ID
    if (sync && collectionID != null) {
      try {
        await provider.syncFileReactions(collectionID, fileID);
      } catch (_) {
        // Ignore sync errors, continue with local data
      }
    }

    // Check if user has liked
    final reactions = await provider.getReactionsForFile(fileID);
    _hasLiked = reactions.any((r) => r.userID == widget.userID && !r.isDeleted);

    // Get comment count
    _commentCount = await provider.getCommentCountForFile(fileID);

    safeRefresh();
  }

  @override
  void dispose() {
    _guestViewEventSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file.canEditMetaInfo &&
        widget.file.canBePanorama() &&
        widget.file.isPanorama() == null) {
      if (lastFileGenID != widget.file.generatedID) {
        lastFileGenID = widget.file.generatedID;
        guardedCheckPanorama(widget.file).ignore();
      }
    }

    final sharedCollectionNotifier = InheritedDetailPageState.maybeOf(
      context,
    )?.isInSharedCollectionNotifier;

    if (sharedCollectionNotifier == null) {
      return _getBottomBar();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: sharedCollectionNotifier,
      builder: (context, _, _) => _getBottomBar(),
    );
  }

  void safeRefresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Widget _getBottomBar() {
    Logger(
      "FileBottomBar",
    ).fine("building bottom bar ${widget.file.generatedID}");

    final isInSharedCollection =
        InheritedDetailPageState.maybeOf(
          context,
        )?.isInSharedCollectionNotifier.value ??
        false;

    final Collection? collection = widget.file.collectionID != null
        ? CollectionsService.instance.getCollectionByID(
            widget.file.collectionID!,
          )
        : null;
    final List<Widget> children = [];
    final bool isOwnedByUser =
        widget.file.ownerID == null || widget.file.ownerID == widget.userID;
    final bool isFileHidden =
        widget.file.isOwner &&
        widget.file.isUploaded &&
        (collection?.isHidden() ?? false);
    if (widget.file is TrashFile) {
      _addTrashOptions(children);
    }

    if (widget.file is! TrashFile) {
      if (isOwnedByUser) {
        children.add(
          Tooltip(
            message: AppLocalizations.of(context).delete,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                icon: Icon(
                  Platform.isAndroid
                      ? Icons.delete_outline
                      : CupertinoIcons.delete,
                  color: Colors.white,
                ),
                onPressed: () async {
                  await _showSingleFileDeleteSheet(widget.file);
                },
              ),
            ),
          ),
        );
      }

      final bool canShowSuggestDelete =
          collection != null &&
          flagService.internalUser &&
          isInSharedCollection &&
          canSuggestDeleteForFile(file: widget.file, collection: collection);

      if (canShowSuggestDelete) {
        children.add(_buildSuggestDeleteButton(collection));
      }

      children.add(
        Tooltip(
          message: AppLocalizations.of(context).share,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: IconButton(
              key: shareButtonKey,
              icon: Icon(
                Platform.isAndroid
                    ? Icons.share_outlined
                    : CupertinoIcons.share,
                color: Colors.white,
              ),
              onPressed: () {
                share(context, [widget.file], shareButtonKey: shareButtonKey);
              },
            ),
          ),
        ),
      );

      // Add to album button for uploaded, non-hidden files
      // Hide when in shared collection (moved to app bar popup menu)
      if (widget.file.isUploaded && !isFileHidden && !isInSharedCollection) {
        children.add(
          Tooltip(
            message: AppLocalizations.of(context).addToAlbum,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                icon: const Icon(
                  EnteIcons.addToAlbum,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  final selectedFiles = SelectedFiles();
                  selectedFiles.files.add(widget.file);
                  showCollectionActionSheet(
                    context,
                    selectedFiles: selectedFiles,
                    actionType: CollectionActionType.addFiles,
                  );
                },
              ),
            ),
          ),
        );
      }

      // Add social icons (heart, comment) for files in shared collections.
      if (isInSharedCollection) {
        children.add(_buildHeartIcon());
        children.add(_buildCommentIcon());
      }
    }
    return ValueListenableBuilder(
      valueListenable: widget.enableFullScreenNotifier,
      builder: (BuildContext context, bool isFullScreen, _) {
        return IgnorePointer(
          ignoring: isFullScreen || isGuestView,
          child: AnimatedOpacity(
            opacity: isFullScreen || isGuestView ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0, 0.8, 1],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSingleFileDeleteSheet(EnteFile file) async {
    await showSingleFileDeleteSheet(
      context,
      file,
      onFileRemoved: widget.onFileRemoved,
      isLocalOnlyContext: widget.isLocalOnlyContext,
    );
  }

  void _addTrashOptions(List<Widget> children) {
    children.add(
      Tooltip(
        message: AppLocalizations.of(context).restore,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IconButton(
            icon: const Icon(Icons.restore_outlined, color: Colors.white),
            onPressed: () {
              final selectedFiles = SelectedFiles();
              selectedFiles.toggleSelection(widget.file);
              showCollectionActionSheet(
                context,
                selectedFiles: selectedFiles,
                actionType: CollectionActionType.restoreFiles,
              );
            },
          ),
        ),
      ),
    );

    children.add(
      Tooltip(
        message: AppLocalizations.of(context).delete,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IconButton(
            icon: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.white,
            ),
            onPressed: () async {
              final trashedFile = <TrashFile>[];
              trashedFile.add(widget.file as TrashFile);
              if (await deleteFromTrash(context, trashedFile) == true) {
                if (!mounted) return;
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestDeleteButton(Collection collection) {
    return Tooltip(
      message: AppLocalizations.of(context).suggestDeletion,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: IconButton(
          icon: const Icon(Icons.flag_outlined, color: Colors.white),
          onPressed: () => _onSuggestDelete(collection),
        ),
      ),
    );
  }

  Widget _buildHeartIcon() {
    return Tooltip(
      message: AppLocalizations.of(context).like,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: GestureDetector(
          onLongPress: _showLikesBottomSheet,
          child: IconButton(
            style: IconButton.styleFrom(
              overlayColor: WidgetStateColor.transparent,
            ),
            onPressed: _toggleReaction,
            icon: Icon(
              _hasLiked ? EnteIcons.likeFilled : EnteIcons.likeStroke,
              color: _hasLiked ? const Color(0xFF08C225) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction() async {
    final file = widget.file;
    if (file.uploadedFileID == null ||
        file.collectionID == null ||
        widget.userID == null) {
      return;
    }

    // If already liked, unlike from ALL shared collections
    if (_hasLiked) {
      await _unlikeFromAllCollections();
      return;
    }

    // Check how many shared collections contain this file
    final sharedCount = await CollectionsService.instance
        .getSharedCollectionCountForFile(file.uploadedFileID!);

    if (sharedCount <= 1) {
      // Single shared collection: like directly
      final previousState = _hasLiked;
      _hasLiked = true;
      safeRefresh();

      try {
        await SocialDataProvider.instance.toggleReaction(
          userID: widget.userID!,
          collectionID: file.collectionID!,
          fileID: file.uploadedFileID,
        );
      } catch (e) {
        _logger.severe("Failed to like photo", e);
        if (mounted) {
          _hasLiked = previousState;
          safeRefresh();
          showShortToast(context, "Failed to like photo");
        }
      }
    } else {
      // Multiple shared collections: show selector bottom sheet
      if (!mounted) return;
      await showLikeCollectionSelectorSheet(
        context,
        fileID: file.uploadedFileID!,
        currentUserID: widget.userID!,
        file: file,
      );
      // Refresh state after sheet closes to sync heart icon
      await _updateSocialState();
    }
  }

  /// Removes the user's like from all shared collections containing this file
  Future<void> _unlikeFromAllCollections() async {
    final file = widget.file;
    if (file.uploadedFileID == null || widget.userID == null) return;

    final currentUserID = widget.userID!;
    final fileID = file.uploadedFileID!;

    // Optimistic UI update
    final previousState = _hasLiked;
    _hasLiked = false;
    safeRefresh();

    try {
      // Get all collections containing this file
      final collectionIDs = await FilesDB.instance.getAllCollectionIDsOfFile(
        fileID,
      );

      // Filter to shared collections
      final sharedCollections = collectionIDs
          .map((id) => CollectionsService.instance.getCollectionByID(id))
          .whereType<Collection>()
          .where((c) => c.hasSharees || c.hasLink || !c.isOwner(currentUserID))
          .toList();

      // Track failures
      int failedCount = 0;

      // Unlike from each collection where user has an active like
      for (final collection in sharedCollections) {
        try {
          final reactions = await SocialDataProvider.instance
              .getReactionsForFileInCollection(fileID, collection.id);

          final userReaction = reactions.firstWhereOrNull(
            (r) => r.userID == currentUserID && !r.isDeleted,
          );

          if (userReaction != null) {
            await SocialDataProvider.instance.toggleReaction(
              userID: currentUserID,
              collectionID: collection.id,
              fileID: fileID,
            );
          }
        } catch (e) {
          failedCount++;
          debugPrint("Failed to unlike from ${collection.displayName}: $e");
        }
      }

      // Show toast and rollback if any failed
      if (failedCount > 0 && mounted) {
        _hasLiked = previousState;
        safeRefresh();
        showShortToast(context, "Failed to unlike photo");
      }
    } catch (e) {
      // Rollback on error (e.g., fetching collections failed)
      debugPrint("Failed to unlike from all collections: $e");
      if (mounted) {
        _hasLiked = previousState;
        safeRefresh();
        showShortToast(context, "Failed to remove like");
      }
    }
  }

  Future<void> _onSuggestDelete(Collection collection) async {
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

  void _showLikesBottomSheet() {
    final file = widget.file;
    if (file.uploadedFileID == null || file.collectionID == null) return;

    showLikesBottomSheet(
      context,
      fileID: file.uploadedFileID!,
      initialCollectionID: file.collectionID!,
    );
  }

  Widget _buildCommentIcon() {
    return Tooltip(
      message: AppLocalizations.of(context).comments,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: IconButton(
          onPressed: _openCommentsScreen,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(EnteIcons.commentBubbleStroke, color: Colors.white),
              if (_commentCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: Text(
                      _commentCount > 99 ? '99+' : _commentCount.toString(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCommentsScreen() {
    final file = widget.file;
    if (file.collectionID == null) return;

    showFileCommentsBottomSheet(
      context,
      collectionID: file.collectionID!,
      fileID: file.uploadedFileID!,
    ).then((_) {
      // Refresh comment count when returning from comments bottom sheet
      _updateSocialState();
    });
  }
}
