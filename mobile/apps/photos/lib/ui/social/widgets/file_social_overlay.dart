import "dart:async";

import "package:collection/collection.dart";
import "package:ente_components/theme/text_styles.dart" as component;
import "package:ente_icons/ente_icons.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/models/social/comment_author_utils.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/social/comments_screen.dart";
import "package:photos/ui/social/like_collection_selector_sheet.dart";
import "package:photos/ui/social/likes_bottom_sheet.dart";

final _logger = Logger("FileSocialOverlay");

const _likedColor = Color(0xFF08C225);
const _socialControlsSize = 48.0;
// TODO: Restore both icons to 24px after updating their ente_icons assets to
// follow HugeIcons sizing guidelines.
const _likeIconSize = 25.0;
const _commentIconSize = 26.0;
const _likeIconPadding = EdgeInsets.all(11.5);
const _commentIconPadding = EdgeInsets.all(11);
const _socialIconShadows = [Shadow(color: Color(0x26000000), blurRadius: 12)];
const _countBadgeShadows = [BoxShadow(color: Color(0x1F000000), blurRadius: 4)];
const _latestCommentShadows = [
  BoxShadow(color: Color(0x14000000), blurRadius: 4),
];

Duration _motionDuration(BuildContext context, int milliseconds) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// Social content for a file. The host owns placement and visibility effects.
class FileSocialOverlay extends StatefulWidget {
  final EnteFile file;
  final int? currentUserID;

  /// The collection the viewer was opened from, or null when there is no
  /// opening collection context. Memories must not pass a deduped file row's
  /// collection ID here.
  final int? openingCollectionID;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final ValueChanged<bool>? onVisibilityChanged;

  const FileSocialOverlay({
    required this.file,
    required this.currentUserID,
    required this.openingCollectionID,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.onVisibilityChanged,
    super.key,
  });

  @override
  State<FileSocialOverlay> createState() => _FileSocialOverlayState();
}

class _FileSocialOverlayState extends State<FileSocialOverlay> {
  bool _hasEligibleSharedCollections = false;
  bool _hasLiked = false;
  int _commentCount = 0;
  Comment? _latestComment;
  User? _latestCommentAuthor;
  int? _loadedFileID;
  int _latestRefreshID = 0;
  final _fileIDsWithReactionUpdateInProgress = <int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSocialState());
  }

  @override
  void didUpdateWidget(covariant FileSocialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.uploadedFileID != widget.file.uploadedFileID) {
      unawaited(_refreshSocialState());
    }
  }

  void _clearSocialState() {
    _loadedFileID = null;
    _hasEligibleSharedCollections = false;
    _hasLiked = false;
    _commentCount = 0;
    _latestComment = null;
    _latestCommentAuthor = null;
  }

  bool _isCurrentSocialRefresh(int refreshID) {
    return mounted && refreshID == _latestRefreshID;
  }

  bool _isOpenedFromHiddenCollection() {
    final openingCollectionID = widget.openingCollectionID;
    return openingCollectionID != null &&
        CollectionsService.instance.getHiddenCollectionIds().contains(
          openingCollectionID,
        );
  }

  Future<void> _refreshSocialState() async {
    // Recheck that this refresh is still current after every await.
    final fileID = widget.file.uploadedFileID;
    final currentUserID = widget.currentUserID;
    final refreshID = ++_latestRefreshID;

    if (fileID == null || currentUserID == null) {
      _clearSocialState();
      widget.onVisibilityChanged?.call(false);
      return;
    }

    try {
      final collectionIDs = await CollectionsService.instance
          .getSharedCollectionIDsForFile(
            fileID,
            includeHidden: _isOpenedFromHiddenCollection(),
          );
      if (!_isCurrentSocialRefresh(refreshID)) {
        return;
      }

      if (collectionIDs.isEmpty) {
        setState(_clearSocialState);
        widget.onVisibilityChanged?.call(false);
        return;
      }

      final provider = SocialDataProvider.instance;
      final results = await Future.wait<Object?>([
        provider.hasUserReactedToFileInCollections(
          fileID,
          currentUserID,
          collectionIDs,
        ),
        provider.getCommentCountForFileInCollections(fileID, collectionIDs),
        provider.getLatestCommentForFile(
          fileID,
          candidateCollectionIDs: collectionIDs,
        ),
      ]);
      if (!_isCurrentSocialRefresh(refreshID)) {
        return;
      }

      final hasLiked = results[0] as bool;
      final commentCount = results[1] as int;
      final latestComment = results[2] as Comment?;
      User? latestCommentAuthor;
      if (latestComment != null) {
        final anonDisplayNames = latestComment.isAnonymous
            ? await provider.getAnonDisplayNamesForCollection(
                latestComment.collectionID,
              )
            : const <String, String>{};
        if (!_isCurrentSocialRefresh(refreshID)) {
          return;
        }

        latestCommentAuthor = CommentAuthorResolver().resolve(
          comment: latestComment,
          anonDisplayNames: anonDisplayNames,
          registeredUserResolver: (userID) => CollectionsService.instance
              .getFileOwner(userID, latestComment.collectionID),
        );
      }

      if (!_isCurrentSocialRefresh(refreshID)) {
        return;
      }
      setState(() {
        _hasEligibleSharedCollections = true;
        _hasLiked = hasLiked;
        _commentCount = commentCount;
        _latestComment = latestComment;
        _latestCommentAuthor = latestCommentAuthor;
        _loadedFileID = fileID;
      });
      widget.onVisibilityChanged?.call(true);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to refresh social overlay for file $fileID",
        error,
        stackTrace,
      );
      if (_isCurrentSocialRefresh(refreshID) && _loadedFileID != fileID) {
        setState(_clearSocialState);
        widget.onVisibilityChanged?.call(false);
      }
    }
  }

  Future<void> _toggleReaction() async {
    final file = widget.file;
    final fileID = file.uploadedFileID;
    final currentUserID = widget.currentUserID;
    if (fileID == null ||
        currentUserID == null ||
        _fileIDsWithReactionUpdateInProgress.contains(fileID)) {
      return;
    }

    _fileIDsWithReactionUpdateInProgress.add(fileID);
    try {
      if (_hasLiked) {
        await _unlikeFromAllCollections(fileID, currentUserID);
        return;
      }

      final sharedCollections = await CollectionsService.instance
          .getSharedCollectionsForFile(
            fileID,
            includeHidden: _isOpenedFromHiddenCollection(),
          );
      if (!mounted ||
          widget.file.uploadedFileID != fileID ||
          sharedCollections.isEmpty) {
        return;
      }

      if (sharedCollections.length == 1) {
        final previousState = _hasLiked;
        setState(() => _hasLiked = true);
        try {
          await SocialDataProvider.instance.toggleReaction(
            userID: currentUserID,
            collectionID: sharedCollections.single.id,
            fileID: fileID,
          );
        } catch (error, stackTrace) {
          _logger.warning("Failed to like photo", error, stackTrace);
          if (mounted && widget.file.uploadedFileID == fileID) {
            setState(() => _hasLiked = previousState);
            _showFailedToUpdateLikeToast();
          }
        }
        return;
      }

      await _runSheetAndRefresh(
        () => showLikeCollectionSelectorSheet(
          context,
          fileID: fileID,
          currentUserID: currentUserID,
          collections: sharedCollections,
          file: file,
        ),
      );
    } finally {
      _fileIDsWithReactionUpdateInProgress.remove(fileID);
    }
  }

  Future<void> _unlikeFromAllCollections(int fileID, int currentUserID) async {
    final previousState = _hasLiked;
    setState(() => _hasLiked = false);

    try {
      final sharedCollections = await CollectionsService.instance
          .getSharedCollectionsForFile(fileID, includeHidden: true);
      var failedCount = 0;
      for (final collection in sharedCollections) {
        try {
          final reactions = await SocialDataProvider.instance
              .getReactionsForFileInCollection(fileID, collection.id);
          final userReaction = reactions.firstWhereOrNull(
            (reaction) => reaction.userID == currentUserID,
          );
          if (userReaction != null) {
            await SocialDataProvider.instance.toggleReaction(
              userID: currentUserID,
              collectionID: collection.id,
              fileID: fileID,
            );
          }
        } catch (error, stackTrace) {
          failedCount++;
          _logger.warning(
            "Failed to unlike from ${collection.displayName}",
            error,
            stackTrace,
          );
        }
      }

      if (failedCount > 0 && mounted && widget.file.uploadedFileID == fileID) {
        setState(() => _hasLiked = previousState);
        _showFailedToUpdateLikeToast();
      }
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to unlike from all collections",
        error,
        stackTrace,
      );
      if (mounted && widget.file.uploadedFileID == fileID) {
        setState(() => _hasLiked = previousState);
        _showFailedToUpdateLikeToast();
      }
    }
  }

  void _showFailedToUpdateLikeToast() {
    if (flagService.internalUser || kDebugMode) {
      showShortToast(context, AppLocalizations.of(context).failedToUpdateLike);
    }
  }

  Future<void> _showLikes() async {
    final fileID = widget.file.uploadedFileID;
    if (fileID == null) return;
    await _runSheetAndRefresh(() async {
      final sharedCollections = await CollectionsService.instance
          .getSharedCollectionsForFile(
            fileID,
            includeHidden: _isOpenedFromHiddenCollection(),
          );
      if (!mounted ||
          widget.file.uploadedFileID != fileID ||
          sharedCollections.isEmpty) {
        return;
      }
      final initialCollection = sharedCollections.firstWhereOrNull(
        (collection) => collection.id == widget.openingCollectionID,
      );
      await showLikesBottomSheet(
        context,
        fileID: fileID,
        initialCollectionID:
            initialCollection?.id ?? sharedCollections.first.id,
        sharedCollections: sharedCollections,
      );
    });
  }

  Future<void> _openComments({Comment? comment}) async {
    final fileID = widget.file.uploadedFileID;
    if (fileID == null) return;
    await _runSheetAndRefresh(() async {
      final sharedCollections = await CollectionsService.instance
          .getSharedCollectionsForFile(
            fileID,
            includeHidden: _isOpenedFromHiddenCollection(),
          );
      if (!mounted ||
          widget.file.uploadedFileID != fileID ||
          sharedCollections.isEmpty) {
        return;
      }

      Collection? commentCollection;
      Collection? openingCollection;
      Collection? latestCommentCollection;
      for (final collection in sharedCollections) {
        if (collection.id == comment?.collectionID) {
          commentCollection = collection;
        }
        if (collection.id == widget.openingCollectionID) {
          openingCollection = collection;
        }
        if (collection.id == _latestComment?.collectionID) {
          latestCommentCollection = collection;
        }
      }
      final initialCollection =
          commentCollection ??
          latestCommentCollection ??
          openingCollection ??
          sharedCollections.first;

      await showFileCommentsBottomSheet(
        context,
        collectionID: initialCollection.id,
        fileID: fileID,
        sharedCollections: sharedCollections,
      );
    });
  }

  Future<void> _runSheetAndRefresh(Future<void> Function() showSheet) async {
    widget.onInteractionStart?.call();
    try {
      await showSheet();
      await _refreshSocialState();
    } finally {
      widget.onInteractionEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasEligibleSharedCollections) {
      return const SizedBox.shrink();
    }

    final latestComment = _latestComment;
    final latestCommentAuthor = _latestCommentAuthor;
    final latestCommentPill =
        latestComment != null && latestCommentAuthor != null
        ? Transform.translate(
            key: const ValueKey("latest-comment"),
            offset: const Offset(0, 8),
            child: _LatestCommentPill(
              comment: latestComment,
              author: latestCommentAuthor,
              width: _latestCommentPillWidth(
                context,
                latestComment.data,
                MediaQuery.sizeOf(context).width * 0.6,
              ),
              currentUserID: widget.currentUserID!,
              onTap: () => _openComments(comment: latestComment),
            ),
          )
        : const SizedBox.shrink();
    return IgnorePointer(
      ignoring: _loadedFileID != widget.file.uploadedFileID,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSwitcher(
            duration: _motionDuration(context, 220),
            reverseDuration: Duration.zero,
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                alignment: Alignment.topRight,
                child: child,
              ),
            ),
            child: latestCommentPill,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: AppLocalizations.of(context).like,
                child: GestureDetector(
                  onLongPress: _showLikes,
                  child: SizedBox.square(
                    dimension: _socialControlsSize,
                    child: IconButton(
                      padding: _likeIconPadding,
                      style: IconButton.styleFrom(
                        overlayColor: WidgetStateColor.transparent,
                      ),
                      onPressed: _toggleReaction,
                      icon: Icon(
                        _hasLiked ? EnteIcons.likeFilled : EnteIcons.likeStroke,
                        color: _hasLiked ? _likedColor : Colors.white,
                        size: _likeIconSize,
                        shadows: _socialIconShadows,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Tooltip(
                message: AppLocalizations.of(context).comments,
                child: SizedBox.square(
                  dimension: _socialControlsSize,
                  child: IconButton(
                    padding: _commentIconPadding,
                    onPressed: _openComments,
                    icon: _CommentBadgeIcon(count: _commentCount),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _latestCommentPillWidth(
  BuildContext context,
  String comment,
  double maxWidth,
) {
  final textPainter = TextPainter(
    text: TextSpan(
      text: comment,
      style: component.TextStyles.mini.copyWith(color: Colors.black),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
    ellipsis: "…",
  )..layout(maxWidth: maxWidth - 32);
  final width = textPainter.width + 32;
  textPainter.dispose();
  return width;
}

class _LatestCommentPill extends StatefulWidget {
  final Comment comment;
  final User author;
  final double width;
  final int currentUserID;
  final VoidCallback onTap;

  const _LatestCommentPill({
    required this.comment,
    required this.author,
    required this.width,
    required this.currentUserID,
    required this.onTap,
  });

  @override
  State<_LatestCommentPill> createState() => _LatestCommentPillState();
}

class _LatestCommentPillState extends State<_LatestCommentPill> {
  bool _showText = true;

  @override
  void didUpdateWidget(_LatestCommentPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id ||
        oldWidget.comment.data != widget.comment.data) {
      _showText = oldWidget.width == widget.width;
    }
  }

  void _showTextAfterResize() {
    if (!_showText) {
      setState(() => _showText = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = component.TextStyles.mini.copyWith(color: Colors.black);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: _latestCommentShadows,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: AnimatedSize(
              duration: _motionDuration(context, 220),
              curve: Curves.easeOutExpo,
              alignment: Alignment.bottomRight,
              onEnd: _showTextAfterResize,
              child: SizedBox(
                width: widget.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Opacity(
                    opacity: _showText ? 1 : 0,
                    child: Text(
                      widget.comment.data,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -3,
            top: -6,
            child: Container(
              width: 22,
              height: 22,
              padding: const EdgeInsets.all(1),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: UserAvatarWidget(
                widget.author,
                type: AvatarType.small,
                currentUserID: widget.currentUserID,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBadgeIcon extends StatelessWidget {
  final int count;

  const _CommentBadgeIcon({required this.count});

  @override
  Widget build(BuildContext context) {
    final displayCount = count > 99 ? "99+" : count.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          EnteIcons.commentBubbleStroke,
          color: Colors.white,
          size: _commentIconSize,
          shadows: _socialIconShadows,
        ),
        Positioned(
          right: -7,
          top: -7,
          child: AnimatedSwitcher(
            duration: _motionDuration(context, 160),
            reverseDuration: _motionDuration(context, 120),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: count > 0
                ? Container(
                    key: const ValueKey(true),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: _countBadgeShadows,
                      borderRadius: BorderRadius.all(Radius.circular(19)),
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: _motionDuration(context, 120),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Text(
                          displayCount,
                          key: ValueKey(displayCount),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey(false)),
          ),
        ),
      ],
    );
  }
}
