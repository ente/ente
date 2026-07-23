import "dart:async";

import "package:ente_components/theme/text_styles.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/social/feed_data_provider.dart";
import "package:photos/models/social/feed_item.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import 'package:photos/services/social_notification_coordinator.dart';
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/social/comments_screen.dart";
import "package:photos/ui/social/social_actor_contact_navigation.dart";
import "package:photos/ui/social/widgets/feed_empty_state.dart";
import "package:photos/ui/social/widgets/feed_item_widget.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";

final _logger = Logger("FeedScreen");

class FeedNavigationTarget {
  final FeedItemType type;
  final int collectionID;
  final int? fileID;
  final String? commentID;

  const FeedNavigationTarget({
    required this.type,
    required this.collectionID,
    this.fileID,
    this.commentID,
  });

  static FeedNavigationTarget? fromUri(Uri uri) {
    final typeRaw = uri.queryParameters['type'];
    final collectionRaw = uri.queryParameters['collectionID'];
    if (typeRaw == null || collectionRaw == null) {
      _logger.warning("Invalid feed URI: missing type or collectionID in $uri");
      return null;
    }
    final collectionID = int.tryParse(collectionRaw);
    if (collectionID == null) {
      _logger.warning(
        "Invalid feed URI: invalid collectionID '$collectionRaw'",
      );
      return null;
    }
    FeedItemType type;
    try {
      type = FeedItemType.values.byName(typeRaw);
    } catch (_) {
      _logger.warning("Invalid feed URI: unknown type '$typeRaw'");
      return null;
    }
    final fileIDRaw = uri.queryParameters['fileID'];
    final fileID = fileIDRaw != null && fileIDRaw.isNotEmpty
        ? int.tryParse(fileIDRaw)
        : null;
    final commentIDRaw = uri.queryParameters['commentID'];
    final commentID = commentIDRaw != null && commentIDRaw.isNotEmpty
        ? commentIDRaw
        : null;
    return FeedNavigationTarget(
      type: type,
      collectionID: collectionID,
      fileID: fileID,
      commentID: commentID,
    );
  }
}

/// Screen that displays the user's activity feed.
///
/// Shows likes, comments, and replies on the user's photos and comments.
class FeedScreen extends StatefulWidget {
  final FeedNavigationTarget? initialTarget;
  final bool showBackButton;

  const FeedScreen({super.key, this.initialTarget, this.showBackButton = true});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _kInitialFeedLimit = 50;
  static const _kFeedLoadMoreStep = 50;
  static const _kMaxFeedLimit = 500;
  static const _kLoadMoreThresholdPx = 200.0;
  static const _kFeedTabIndex = 2;

  List<FeedItem> _feedItems = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentLimit = _kInitialFeedLimit;
  late final int _currentUserID;
  FeedNavigationTarget? _pendingNavigationTarget;
  bool _didHandleNavigationTarget = false;
  bool _isOpeningNavigationTarget = false;
  bool _hasMarkedSocialSeen = false;
  bool _hasStartedLoading = false;
  StreamSubscription<TabChangedEvent>? _tabChangedEventSubscription;
  final Set<String> _suppressedForwardHeroPrefixes = <String>{};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _navigationTargetItemKey = GlobalKey();

  /// Map of collectionID -> (anonUserID -> displayName)
  Map<int, Map<String, String>> _anonDisplayNamesByCollection = {};

  @override
  void initState() {
    super.initState();
    _currentUserID = Configuration.instance.getUserID() ?? 0;
    _pendingNavigationTarget = widget.initialTarget;
    _scrollController.addListener(_onScroll);
    if (widget.showBackButton) {
      _activateFeed();
    } else {
      _tabChangedEventSubscription = Bus.instance.on<TabChangedEvent>().listen((
        event,
      ) {
        if (event.selectedIndex == _kFeedTabIndex) {
          _activateFeed();
        }
      });
    }
  }

  @override
  void dispose() {
    _tabChangedEventSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _markSocialSeenOnce() {
    if (_hasMarkedSocialSeen) return;
    _hasMarkedSocialSeen = true;
    unawaited(SocialNotificationCoordinator.instance.markSocialSeen());
  }

  void _activateFeed() {
    _markSocialSeenOnce();
    if (_hasStartedLoading) return;
    _hasStartedLoading = true;
    _loadFeedItems();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _kLoadMoreThresholdPx) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFeedItems() async {
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _currentLimit = _kInitialFeedLimit;
      _hasMore = true;
    });

    // Load local data first
    final items = await FeedDataProvider.instance.getFeedItems(
      limit: _currentLimit,
    );

    // Load anon display names for all collections in feed
    final anonNames = await _loadAnonDisplayNames(items);

    if (mounted) {
      setState(() {
        _feedItems = items;
        _anonDisplayNamesByCollection = anonNames;
        _isLoading = false;
        _hasMore =
            _currentLimit < _kMaxFeedLimit && items.length >= _currentLimit;
      });
    }
    _tryOpenNavigationTarget();

    // Sync in background and refresh
    unawaited(_syncAndRefresh());
  }

  Future<Map<int, Map<String, String>>> _loadAnonDisplayNames(
    List<FeedItem> items,
  ) async {
    final collectionIDs = items.map((e) => e.collectionID).toSet();
    final results = <int, Map<String, String>>{};

    await Future.wait(
      collectionIDs.map((collectionID) async {
        final names = await SocialDataProvider.instance
            .getAnonDisplayNamesForCollection(collectionID);
        results[collectionID] = names;
      }),
    );

    return results;
  }

  Future<void> _syncAndRefresh() async {
    try {
      final hasNewSocialData = await FeedDataProvider.instance
          .syncAllSharedCollections();

      if (!mounted) return;
      if (!hasNewSocialData) return;

      // Reload feed items after sync
      final freshItems = await FeedDataProvider.instance.getFeedItems(
        limit: _currentLimit,
      );

      // Reload anon display names for new items
      final freshAnonNames = await _loadAnonDisplayNames(freshItems);

      if (mounted) {
        setState(() {
          _feedItems = freshItems;
          _anonDisplayNamesByCollection = freshAnonNames;
          _hasMore =
              _currentLimit < _kMaxFeedLimit &&
              freshItems.length >= _currentLimit;
        });
      }
      _tryOpenNavigationTarget();
    } catch (_) {
      // Ignore sync errors, local data is already displayed
    }
  }

  Future<void> _onRefresh() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _currentLimit = _kInitialFeedLimit;
        _hasMore = true;
      });
    }

    final items = await FeedDataProvider.instance.getFeedItems(
      limit: _currentLimit,
    );
    final anonNames = await _loadAnonDisplayNames(items);

    if (mounted) {
      setState(() {
        _feedItems = items;
        _anonDisplayNamesByCollection = anonNames;
        _isLoading = false;
        _hasMore =
            _currentLimit < _kMaxFeedLimit && items.length >= _currentLimit;
      });
    }
    _tryOpenNavigationTarget();

    await _syncAndRefresh();
  }

  Future<void> _loadMore() async {
    if (!mounted || _isLoading || _isLoadingMore || !_hasMore) {
      return;
    }

    final nextLimit = (_currentLimit + _kFeedLoadMoreStep).clamp(
      _kInitialFeedLimit,
      _kMaxFeedLimit,
    );
    if (nextLimit <= _currentLimit) {
      if (mounted) {
        setState(() => _hasMore = false);
      }
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final items = await FeedDataProvider.instance.getFeedItems(
        limit: nextLimit,
      );
      final anonNames = await _loadAnonDisplayNames(items);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentLimit = nextLimit;
        _feedItems = items;
        _anonDisplayNamesByCollection = anonNames;
        _hasMore =
            _currentLimit < _kMaxFeedLimit && items.length >= _currentLimit;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _tryOpenNavigationTarget() {
    if (_didHandleNavigationTarget || _isOpeningNavigationTarget) {
      return;
    }
    final target = _pendingNavigationTarget;
    if (target == null) return;
    _isOpeningNavigationTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isOpeningNavigationTarget = false;
        return;
      }
      final opened = await _openNavigationTarget(target);
      if (opened && mounted) {
        _didHandleNavigationTarget = true;
        _pendingNavigationTarget = null;
      }
      _isOpeningNavigationTarget = false;
    });
  }

  Future<bool> _openNavigationTarget(FeedNavigationTarget target) async {
    if (!mounted) return false;
    if (target.type == FeedItemType.sharedPhoto ||
        target.type == FeedItemType.sharedCollection) {
      return _focusFeedItemTarget(target);
    }
    if (target.type == FeedItemType.photoLike) {
      final fileID = target.fileID;
      if (fileID == null) return false;
      final file = await FilesDB.instance.getUploadedFile(
        fileID,
        target.collectionID,
      );
      if (file == null || !mounted) return false;
      unawaited(
        routeToPage(
          context,
          DetailPage(DetailPageConfiguration([file], 0, "feed_item")),
          forceCustomPageRoute: true,
        ),
      );
      return true;
    }
    var fileID = target.fileID;
    if (fileID == null && target.commentID != null) {
      final comment = await SocialDataProvider.instance.getCommentById(
        target.commentID!,
      );
      fileID = comment?.fileID;
    }
    if (fileID == null) return false;
    final file = await FilesDB.instance.getUploadedFile(
      fileID,
      target.collectionID,
    );
    if (file == null || !mounted) return false;
    final capturedFileID = fileID;
    final highlightID = target.commentID;
    unawaited(
      routeToPage(
        context,
        DetailPage(
          DetailPageConfiguration(
            [file],
            0,
            "feed_comment",
            onPageReady: (detailContext) {
              showFileCommentsBottomSheet(
                detailContext,
                collectionID: target.collectionID,
                fileID: capturedFileID,
                highlightCommentID: highlightID,
              );
            },
          ),
        ),
        forceCustomPageRoute: true,
      ),
    );
    return true;
  }

  Future<bool> _focusFeedItemTarget(FeedNavigationTarget target) async {
    if (target.type == FeedItemType.sharedPhoto && target.fileID == null) {
      _logger.warning(
        "Shared-photo notification target is missing fileID: $target",
      );
      return false;
    }
    var targetIndex = _findFeedItemIndexForTarget(target);
    while (targetIndex == -1 && _hasMore) {
      final previousLimit = _currentLimit;
      await _loadMore();
      if (!mounted || _currentLimit == previousLimit) {
        break;
      }
      targetIndex = _findFeedItemIndexForTarget(target);
    }

    if (targetIndex == -1) {
      _logger.warning("Could not find feed item for notification target");
      return false;
    }

    return _scrollToFeedItemIndex(targetIndex);
  }

  int _findFeedItemIndexForTarget(FeedNavigationTarget target) {
    return _feedItems.indexWhere(
      (item) => _feedItemMatchesNavigationTarget(item, target),
    );
  }

  bool _feedItemMatchesNavigationTarget(
    FeedItem item,
    FeedNavigationTarget target,
  ) {
    if (item.type != target.type || item.collectionID != target.collectionID) {
      return false;
    }

    final targetCommentID = target.commentID;
    if (targetCommentID != null && targetCommentID.isNotEmpty) {
      return item.commentID == targetCommentID;
    }

    final targetFileID = target.fileID;
    if (target.type == FeedItemType.sharedPhoto && targetFileID == null) {
      return false;
    }
    if (targetFileID == null) {
      return true;
    }
    if (item.fileID == targetFileID) {
      return true;
    }

    final sharedFileIDs = item.sharedFileIDs;
    if (sharedFileIDs != null && sharedFileIDs.contains(targetFileID)) {
      return true;
    }
    return false;
  }

  bool _shouldUseNavigationTargetKey(FeedItem item) {
    final target = _pendingNavigationTarget;
    if (target == null ||
        (target.type != FeedItemType.sharedPhoto &&
            target.type != FeedItemType.sharedCollection)) {
      return false;
    }
    if (target.type == FeedItemType.sharedPhoto && target.fileID == null) {
      return false;
    }
    return _feedItemMatchesNavigationTarget(item, target);
  }

  Future<bool> _scrollToFeedItemIndex(int index) async {
    if (!_scrollController.hasClients) {
      return false;
    }

    // Allow newly loaded rows to be laid out before reading list metrics.
    await Future<void>.delayed(Duration.zero);

    for (var attempt = 0; attempt < 7; attempt++) {
      if (!mounted || !_scrollController.hasClients) {
        return false;
      }

      final targetContext = _navigationTargetItemKey.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) return false;
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return true;
      }

      final position = _scrollController.position;
      final maxExtent = position.maxScrollExtent;
      if (maxExtent <= 0 || _feedItems.length <= 1 || index <= 0) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        final estimatedOffset = (index / (_feedItems.length - 1)) * maxExtent;
        final viewport = position.viewportDimension;
        final sweepStep = viewport > 0 ? viewport * 0.75 : maxExtent * 0.2;
        double nextOffset = estimatedOffset;

        if (attempt > 0) {
          final sweepRing = ((attempt + 1) ~/ 2).toDouble();
          final direction = attempt.isOdd ? -1.0 : 1.0;
          nextOffset += direction * sweepRing * sweepStep;
        }

        nextOffset = nextOffset.clamp(0.0, maxExtent);
        if ((nextOffset - position.pixels).abs() < 1.0) {
          final nudge = viewport > 0 ? viewport * 0.35 : maxExtent * 0.1;
          final nudgeDirection = attempt.isOdd ? 1.0 : -1.0;
          nextOffset = (nextOffset + (nudgeDirection * nudge)).clamp(
            0.0,
            maxExtent,
          );
        }

        await _scrollController.animateTo(
          nextOffset,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : colorScheme.backgroundColour,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: isDark ? null : colorScheme.backgroundColour,
        elevation: 0,
        centerTitle: false,
        leadingWidth: widget.showBackButton ? 48 : null,
        titleSpacing: widget.showBackButton ? 4 : null,
        leading: widget.showBackButton
            ? IconButtonWidget(
                iconButtonType: IconButtonType.primary,
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          AppLocalizations.of(context).feed,
          style: widget.showBackButton
              ? TextStyles.display3.copyWith(color: textTheme.h4Bold.color)
              : TextStyles.display1.copyWith(color: textTheme.h4Bold.color),
        ),
      ),
      body: _isLoading
          ? const Center(child: EnteLoadingWidget(size: 24))
          : _feedItems.isEmpty
          ? FeedEmptyState(
              localGalleryMode:
                  isLocalGalleryMode &&
                  !Configuration.instance.hasConfiguredAccount(),
            )
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: 15,
                  right: 15,
                  bottom:
                      MediaQuery.paddingOf(context).bottom +
                      (widget.showBackButton ? 0 : 88),
                ),
                itemCount: _feedItems.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _feedItems.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: EnteLoadingWidget(size: 20)),
                    );
                  }
                  final item = _feedItems[index];
                  final isLastItem = index == _feedItems.length - 1;
                  final itemKey = _feedItemStableKey(item);
                  final heroTagPrefix = _heroTagPrefixForFeedItem(item);
                  final isForwardHeroSuppressed = _suppressedForwardHeroPrefixes
                      .contains(heroTagPrefix);
                  final key = _shouldUseNavigationTargetKey(item)
                      ? _navigationTargetItemKey
                      : ValueKey(itemKey);
                  return FeedItemWidget(
                    key: key,
                    feedItem: item,
                    heroTagPrefix: heroTagPrefix,
                    enableThumbnailHero: !isForwardHeroSuppressed,
                    currentUserID: _currentUserID,
                    anonDisplayNames:
                        _anonDisplayNamesByCollection[item.collectionID] ??
                        const {},
                    isLastItem: isLastItem,
                    onTap: () =>
                        _handleFeedItemTap(item, heroTagPrefix: heroTagPrefix),
                    onSharedHeaderTap: () => _openSharedCollection(
                      item,
                      heroTagPrefix: heroTagPrefix,
                      jumpToFileID: _jumpFileIDForSharedCollection(
                        type: item.type,
                        sharedFileIDs: item.sharedFileIDs,
                      ),
                    ),
                    onSharedPhotoTap: (fileID) => _openSharedPhotos(
                      item,
                      initialFileID: fileID,
                      heroTagPrefix: heroTagPrefix,
                    ),
                    onSharedExtraCountTap: () => _openSharedCollection(
                      item,
                      jumpToFileID: _jumpFileIDForSharedCollection(
                        type: item.type,
                        sharedFileIDs: item.sharedFileIDs,
                      ),
                    ),
                    onPrimaryActorTap: (user) =>
                        openSocialActorContactDestination(
                          context,
                          user,
                          currentUserID: _currentUserID,
                        ),
                  );
                },
              ),
            ),
    );
  }

  String _feedItemStableKey(FeedItem item) {
    return '${item.type}_${item.fileID}_${item.commentID}_${item.createdAt}';
  }

  String _heroTagPrefixForFeedItem(FeedItem item) {
    return 'feed_item_${_feedItemStableKey(item)}_';
  }

  void _handleFeedItemTap(FeedItem item, {required String heroTagPrefix}) {
    switch (item.type) {
      case FeedItemType.photoLike:
        _openPhoto(item, heroTagPrefix: heroTagPrefix);
        break;
      case FeedItemType.sharedPhoto:
        _openSharedPhotos(item, heroTagPrefix: heroTagPrefix);
        break;
      case FeedItemType.sharedCollection:
        _openSharedCollection(item, heroTagPrefix: heroTagPrefix);
        break;
      case FeedItemType.comment:
      case FeedItemType.reply:
        _openComments(
          item,
          heroTagPrefix: heroTagPrefix,
          disableForwardHero: true,
        );
        break;
      case FeedItemType.commentLike:
      case FeedItemType.replyLike:
        _openComments(item, heroTagPrefix: heroTagPrefix);
        break;
    }
  }

  Future<void> _openSharedCollection(
    FeedItem item, {
    int? jumpToFileID,
    String? heroTagPrefix,
  }) async {
    var collection = CollectionsService.instance.getCollectionByID(
      item.collectionID,
    );
    if (collection == null) {
      try {
        collection = await CollectionsService.instance.fetchCollectionByID(
          item.collectionID,
        );
      } catch (e, s) {
        _logger.warning(
          "Failed to fetch collection ${item.collectionID} for feed shared item",
          e,
          s,
        );
      }
    }

    if (collection == null || !mounted) {
      // Fallback to shared-photos viewer if collection metadata isn't available.
      await _openSharedPhotos(
        item,
        initialFileID: jumpToFileID,
        heroTagPrefix: heroTagPrefix,
      );
      return;
    }

    EnteFile? fileToJumpTo;
    if (jumpToFileID != null) {
      fileToJumpTo = await FilesDB.instance.getUploadedFile(
        jumpToFileID,
        item.collectionID,
      );
    }

    if (!mounted) return;
    unawaited(
      routeToPage(
        context,
        CollectionPage(
          CollectionWithThumbnail(collection, null),
          fileToJumpTo: fileToJumpTo,
        ),
        forceCustomPageRoute: true,
      ),
    );
  }

  int? _jumpFileIDForSharedCollection({
    required FeedItemType type,
    int? fileID,
    List<int>? sharedFileIDs,
  }) {
    if (type != FeedItemType.sharedPhoto) {
      return null;
    }
    if (fileID != null) {
      return fileID;
    }
    if (sharedFileIDs == null || sharedFileIDs.isEmpty) {
      return null;
    }
    return sharedFileIDs.first;
  }

  /// Opens the photo viewer for the feed item, then shows the comments sheet.
  Future<void> _openComments(
    FeedItem item, {
    String? heroTagPrefix,
    bool disableForwardHero = false,
  }) async {
    var fileID = item.fileID;

    if (fileID == null && item.commentID != null) {
      final comment = await SocialDataProvider.instance.getCommentById(
        item.commentID!,
      );
      fileID = comment?.fileID;
    }

    if (fileID == null) return;
    final shouldDisableForwardHero =
        disableForwardHero &&
        heroTagPrefix != null &&
        !_suppressedForwardHeroPrefixes.contains(heroTagPrefix);

    final file = await FilesDB.instance.getUploadedFile(
      fileID,
      item.collectionID,
    );
    if (file == null || !mounted) return;

    final capturedFileID = fileID;
    if (shouldDisableForwardHero) {
      setState(() {
        _suppressedForwardHeroPrefixes.add(heroTagPrefix);
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    // Navigate to the photo first, then show comments sheet after first frame
    unawaited(
      routeToPage(
        context,
        DetailPage(
          DetailPageConfiguration(
            [file],
            0,
            heroTagPrefix ?? "feed_comment",
            onPageReady: (detailContext) {
              showFileCommentsBottomSheet(
                detailContext,
                collectionID: item.collectionID,
                fileID: capturedFileID,
                highlightCommentID: item.commentID,
              );
            },
          ),
        ),
        forceCustomPageRoute: true,
      ),
    );
    if (shouldDisableForwardHero) {
      unawaited(() async {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        setState(() {
          _suppressedForwardHeroPrefixes.remove(heroTagPrefix);
        });
      }());
    }
  }

  /// Opens the photo viewer for the feed item.
  Future<void> _openPhoto(FeedItem item, {String? heroTagPrefix}) async {
    var fileID = item.fileID;

    if (fileID == null && item.commentID != null) {
      final comment = await SocialDataProvider.instance.getCommentById(
        item.commentID!,
      );
      fileID = comment?.fileID;
    }

    if (fileID == null) return;

    final file = await FilesDB.instance.getUploadedFile(
      fileID,
      item.collectionID,
    );
    if (file == null || !mounted) return;

    unawaited(
      routeToPage(
        context,
        DetailPage(
          DetailPageConfiguration([file], 0, heroTagPrefix ?? "feed_item"),
        ),
        forceCustomPageRoute: true,
      ),
    );
  }

  /// Opens a gallery view of the shared photos.
  Future<void> _openSharedPhotos(
    FeedItem item, {
    int? initialFileID,
    String? heroTagPrefix,
  }) async {
    final fileIDs = item.sharedFileIDs;
    if (fileIDs == null || fileIDs.isEmpty) return;

    // Load all files using batch query
    final loadedFiles = await FilesDB.instance.getUploadedFilesBatch(
      fileIDs,
      item.collectionID,
    );
    final files = loadedFiles.whereType<EnteFile>().toList();

    if (files.isEmpty || !mounted) return;

    var initialIndex = 0;
    if (initialFileID != null) {
      final tappedIndex = files.indexWhere(
        (file) => file.uploadedFileID == initialFileID,
      );
      if (tappedIndex >= 0) {
        initialIndex = tappedIndex;
      }
    }

    unawaited(
      routeToPage(
        context,
        DetailPage(
          DetailPageConfiguration(
            files,
            initialIndex,
            heroTagPrefix ?? "feed_shared_photos",
          ),
        ),
        forceCustomPageRoute: true,
      ),
    );
  }
}
