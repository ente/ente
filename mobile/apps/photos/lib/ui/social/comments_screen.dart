import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/comment_deleted_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/models/social/comment_author_utils.dart";
import "package:photos/models/social/reaction.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/services/collections_service.dart";
import 'package:photos/services/social_notification_coordinator.dart';
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/social/social_actor_contact_navigation.dart";
import "package:photos/ui/social/widgets/collection_selector_widget.dart";
import "package:photos/ui/social/widgets/comment_bubble_widget.dart";
import "package:photos/ui/social/widgets/comment_input_widget.dart";

typedef _CommentDraftFileKey = ({int fileID, int userID});
typedef _CommentDraftKey = ({int collectionID, int fileID, int userID});

final Map<_CommentDraftKey, _CommentDraft> _commentDrafts = {};
final Map<_CommentDraftFileKey, int> _lastSelectedDraftCollectionIDs = {};

class _CommentDraft {
  final String text;
  final Comment? replyingTo;

  const _CommentDraft({required this.text, required this.replyingTo});
}

/// Shows the file comments bottom sheet
Future<void> showFileCommentsBottomSheet(
  BuildContext context, {
  required int collectionID,
  required int fileID,
  String? highlightCommentID,
  List<Collection>? sharedCollections,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DraggableCommentsSheet(
      launchContext: context,
      collectionID: collectionID,
      fileID: fileID,
      highlightCommentID: highlightCommentID,
      sharedCollections: sharedCollections,
    ),
  );
}

class _DraggableCommentsSheet extends StatefulWidget {
  final BuildContext launchContext;
  final int collectionID;
  final int fileID;
  final String? highlightCommentID;
  final List<Collection>? sharedCollections;

  const _DraggableCommentsSheet({
    required this.launchContext,
    required this.collectionID,
    required this.fileID,
    this.highlightCommentID,
    this.sharedCollections,
  });

  @override
  State<_DraggableCommentsSheet> createState() =>
      _DraggableCommentsSheetState();
}

class _DraggableCommentsSheetState extends State<_DraggableCommentsSheet> {
  final sheetController = DraggableScrollableController();

  @override
  void dispose() {
    sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 60;
    return DraggableScrollableSheet(
      controller: sheetController,
      initialChildSize: isKeyboardOpen ? 0.95 : 0.6,
      minChildSize: isKeyboardOpen ? 0.8 : 0.4,
      maxChildSize: 0.95,
      snap: isKeyboardOpen ? false : true,
      snapSizes: isKeyboardOpen ? null : const [0.6],
      expand: false,
      builder: (context, scrollController) => FileCommentsBottomSheet(
        launchContext: widget.launchContext,
        collectionID: widget.collectionID,
        fileID: widget.fileID,
        highlightCommentID: widget.highlightCommentID,
        sharedCollections: widget.sharedCollections,
        dragController: scrollController,
        sheetController: sheetController,
      ),
    );
  }
}

class FileCommentsBottomSheet extends StatefulWidget {
  final BuildContext launchContext;
  final int collectionID;
  final int fileID;
  final List<Collection>? sharedCollections;

  /// Optional comment ID to scroll to and highlight.
  final String? highlightCommentID;

  /// Scroll controller for the drag handle (from DraggableScrollableSheet).
  final ScrollController dragController;

  /// Controller to programmatically expand/collapse the sheet.
  final DraggableScrollableController sheetController;

  const FileCommentsBottomSheet({
    required this.launchContext,
    required this.collectionID,
    required this.fileID,
    this.sharedCollections,
    required this.dragController,
    required this.sheetController,
    this.highlightCommentID,
    super.key,
  });

  @override
  State<FileCommentsBottomSheet> createState() =>
      _FileCommentsBottomSheetState();
}

class _FileCommentsBottomSheetState extends State<FileCommentsBottomSheet> {
  static final _logger = Logger('FileCommentsBottomSheet');

  final List<Comment> _comments = [];

  Comment? _replyingTo;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  SendButtonState _sendState = SendButtonState.idle;
  Timer? _sendLoadingTimer;
  bool _hasMoreComments = true;
  int _offset = 0;
  final CommentAuthorResolver _commentAuthorResolver = CommentAuthorResolver();
  final MissingAnonProfileSyncTracker _anonProfileSyncTracker =
      MissingAnonProfileSyncTracker();
  Map<String, String> _anonDisplayNames = {};
  String? _highlightedCommentID;
  bool _hasScrolledToHighlight = false;
  GlobalKey? _highlightedCommentKey;
  String? _scrollTargetCommentID;
  GlobalKey? _scrollTargetKey;
  String? _scrollTargetHighlightID;

  List<CollectionCommentInfo> _sharedCollections = [];
  late int _selectedCollectionID;

  late final TextEditingController _textController;
  late final FocusNode _inputFocusNode;
  late final ScrollController _scrollController;
  late final int _currentUserID;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    unawaited(SocialNotificationCoordinator.instance.markSocialSeen());
    _textController = TextEditingController();
    _textController.addListener(_saveOrClearDraft);
    _inputFocusNode = FocusNode()..addListener(_onInputFocusChange);
    _scrollController = ScrollController()..addListener(_onScroll);
    _currentUserID = Configuration.instance.getUserID()!;
    _selectedCollectionID = _canRestoreDraftCollection
        ? _lastSelectedDraftCollectionIDs[_draftFileKey] ?? widget.collectionID
        : widget.collectionID;
    _highlightedCommentID = widget.highlightCommentID;
    _loadSharedCollections();
  }

  void _onInputFocusChange() {
    if (_inputFocusNode.hasFocus && widget.sheetController.isAttached) {
      widget.sheetController.animateTo(
        0.95,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _sendLoadingTimer?.cancel();
    _textController.removeListener(_saveOrClearDraft);
    _textController.dispose();
    _inputFocusNode.removeListener(_onInputFocusChange);
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isOpenedFromHiddenCollection() => CollectionsService.instance
      .getHiddenCollectionIds()
      .contains(widget.collectionID);

  Future<void> _loadSharedCollections() async {
    final sharedCollectionsList =
        widget.sharedCollections ??
        await CollectionsService.instance.getSharedCollectionsForFile(
          widget.fileID,
          includeHidden: _isOpenedFromHiddenCollection(),
        );

    // Fetch data in parallel
    final sharedCollections = await Future.wait(
      sharedCollectionsList.map((collection) async {
        final commentCount = await SocialDataProvider.instance
            .getCommentCountForFileInCollection(widget.fileID, collection.id);
        final thumbnail = await CollectionsService.instance.getCover(
          collection,
        );
        return CollectionCommentInfo(
          collection: collection,
          commentCount: commentCount,
          thumbnail: thumbnail,
        );
      }),
    );

    if (mounted) {
      if (sharedCollections.isEmpty) {
        _logger.warning(
          'FileCommentsScreen opened for file ${widget.fileID} with no shared collections',
        );
        Navigator.of(context).pop();
        return;
      }

      final savedSelectedCollectionID =
          _lastSelectedDraftCollectionIDs[_draftFileKey];
      final nextSelectedCollectionID =
          _canRestoreDraftCollection &&
              savedSelectedCollectionID != null &&
              sharedCollections.any(
                (info) => info.collection.id == savedSelectedCollectionID,
              )
          ? savedSelectedCollectionID
          : sharedCollections.any(
              (info) => info.collection.id == _selectedCollectionID,
            )
          ? _selectedCollectionID
          : sharedCollections.first.collection.id;

      setState(() {
        _sharedCollections = sharedCollections;
        _selectedCollectionID = nextSelectedCollectionID;
        _restoreDraftForSelectedCollection();
      });

      unawaited(_loadInitialComments());
    }
  }

  Future<void> _loadInitialComments() async {
    setState(() => _isLoading = true);

    // Load local data first for immediate display
    final results = await Future.wait([
      SocialDataProvider.instance.getCommentsForFilePaginated(
        widget.fileID,
        collectionID: _selectedCollectionID,
        limit: _pageSize,
        offset: 0,
      ),
      SocialDataProvider.instance.getAnonDisplayNamesForCollection(
        _selectedCollectionID,
      ),
    ]);

    final comments = results[0] as List<Comment>;
    final anonNames = results[1] as Map<String, String>;

    setState(() {
      _comments.addAll(comments);
      _anonDisplayNames = anonNames;
      _offset = comments.length;
      _hasMoreComments = comments.length == _pageSize;
      _isLoading = false;
    });
    unawaited(_syncMissingAnonDisplayNamesFor(comments));

    // Scroll to highlighted comment if specified
    _scrollToHighlightedComment();

    // Sync in background and refresh if there are changes
    unawaited(_syncAndRefresh());
  }

  Future<void> _syncAndRefresh() async {
    try {
      await SocialDataProvider.instance.syncFileSocialData(
        _selectedCollectionID,
        widget.fileID,
      );

      if (!mounted) return;

      // Reload comments and any already-synced anonymous names after sync.
      final results = await Future.wait([
        SocialDataProvider.instance.getCommentsForFilePaginated(
          widget.fileID,
          collectionID: _selectedCollectionID,
          limit: _pageSize,
          offset: 0,
        ),
        SocialDataProvider.instance.getAnonDisplayNamesForCollection(
          _selectedCollectionID,
        ),
      ]);

      final freshComments = results[0] as List<Comment>;
      final anonNames = results[1] as Map<String, String>;

      if (mounted) {
        setState(() {
          _comments.clear();
          _comments.addAll(freshComments);
          _anonDisplayNames = anonNames;
          _offset = freshComments.length;
          _hasMoreComments = freshComments.length == _pageSize;
        });
        unawaited(_syncMissingAnonDisplayNamesFor(freshComments));
      }
    } catch (_) {
      // Ignore sync errors, local data is already displayed
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasMoreComments) return;

    setState(() => _isLoadingMore = true);

    final comments = await SocialDataProvider.instance
        .getCommentsForFilePaginated(
          widget.fileID,
          collectionID: _selectedCollectionID,
          limit: _pageSize,
          offset: _offset,
        );

    setState(() {
      _comments.addAll(comments);
      _offset += comments.length;
      _hasMoreComments = comments.length == _pageSize;
      _isLoadingMore = false;
    });
    unawaited(_syncMissingAnonDisplayNamesFor(comments));
  }

  Future<void> _syncMissingAnonDisplayNamesFor(List<Comment> comments) async {
    final collectionID = _selectedCollectionID;
    final missingIDs = _anonProfileSyncTracker.nextIDsToSync(
      collectionID: collectionID,
      comments: comments,
      anonDisplayNames: _anonDisplayNames,
    );
    if (missingIDs.isEmpty) {
      return;
    }

    try {
      await SocialDataProvider.instance.syncAnonProfiles(collectionID);
      final anonNames = await SocialDataProvider.instance
          .getAnonDisplayNamesForCollection(collectionID);
      if (!mounted || _selectedCollectionID != collectionID) {
        return;
      }
      setState(() => _anonDisplayNames = anonNames);
    } catch (_) {
      // Missing anonymous names should not block showing comments.
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreComments();
    }
  }

  void _scrollToHighlightedComment() {
    if (_highlightedCommentID == null || _hasScrolledToHighlight) return;

    final index = _comments.indexWhere((c) => c.id == _highlightedCommentID);
    if (index == -1) return;

    _hasScrolledToHighlight = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // Phase 1: Jump to approximate position to bring item into view
      const estimatedItemHeight = 120.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final scrollPosition = (index * estimatedItemHeight).clamp(
        0.0,
        maxScroll,
      );

      _scrollController.jumpTo(scrollPosition);

      // Phase 2: After item is built, use ensureVisible for precise positioning
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final context = _highlightedCommentKey?.currentContext;
        if (context == null) return;

        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutExpo,
        );
      });
    });
  }

  Future<void> _scrollToParentComment(String parentCommentID) async {
    _scrollTargetCommentID =
        parentCommentID; // Set immediately for race detection

    // Check if already loaded
    int index = _comments.indexWhere((c) => c.id == parentCommentID);

    if (index != -1) {
      _performScrollToIndex(index, parentCommentID);
      return;
    }

    // Parent not in loaded comments - need to load more
    while (_hasMoreComments) {
      await _loadMoreComments();

      // Check if user tapped a different parent (race condition)
      if (_scrollTargetCommentID != null &&
          _scrollTargetCommentID != parentCommentID) {
        return; // Abort, another scroll is in progress
      }

      index = _comments.indexWhere((c) => c.id == parentCommentID);
      if (index != -1) {
        _performScrollToIndex(index, parentCommentID);
        return;
      }
    }

    // Parent not found (deleted) - do nothing silently
  }

  void _performScrollToIndex(int index, String commentID) {
    _scrollTargetCommentID = commentID;
    _scrollTargetKey = GlobalKey();
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // Phase 1: Jump to approximate position
      const estimatedItemHeight = 120.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final scrollPosition = (index * estimatedItemHeight).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(scrollPosition);

      // Phase 2: Precise scroll with ensureVisible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final context = _scrollTargetKey?.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutExpo,
          );
        }
        // Clear scroll target and trigger highlight
        _scrollTargetCommentID = null;
        _scrollTargetKey = null;
        if (mounted) {
          setState(() => _scrollTargetHighlightID = commentID);
        }
      });
    });
  }

  void _onCollectionSelected(int collectionID) {
    _saveOrClearDraft();
    setState(() {
      _selectedCollectionID = collectionID;
      _restoreDraftForSelectedCollection();
      _comments.clear();
      _offset = 0;
      _hasMoreComments = true;
      _commentAuthorResolver.clear();
      _anonDisplayNames = {};
    });
    _loadInitialComments();
  }

  Future<Comment?> _getParentComment(String parentCommentId) {
    return SocialDataProvider.instance.getCommentById(parentCommentId);
  }

  Future<List<Reaction>> _getReactionsForComment(String commentId) {
    return SocialDataProvider.instance.getReactionsForComment(commentId);
  }

  void _onReplyTap(Comment comment) {
    setState(() => _replyingTo = comment);
    _saveOrClearDraft();
    _inputFocusNode.requestFocus();
  }

  User _getUserForComment(Comment comment) {
    return _commentAuthorResolver.resolve(
      comment: comment,
      anonDisplayNames: _anonDisplayNames,
      registeredUserResolver: (userID) => CollectionsService.instance
          .getFileOwner(userID, _selectedCollectionID),
    );
  }

  void _dismissReply() {
    setState(() => _replyingTo = null);
    _saveOrClearDraft();
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sendState != SendButtonState.idle) return;
    final collectionID = _selectedCollectionID;
    final replyingTo = _replyingTo;

    // Mark as sending internally (blocks duplicate sends) but don't show UI yet
    _sendState = SendButtonState.sending;

    // Only show loading indicator after 400ms delay
    _sendLoadingTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _sendState == SendButtonState.sending) {
        setState(() {});
      }
    });

    try {
      final result = await SocialDataProvider.instance.addComment(
        collectionID: collectionID,
        text: text,
        fileID: widget.fileID,
        parentCommentID: replyingTo?.id,
      );
      _sendLoadingTimer?.cancel();

      if (result == null) {
        _logger.warning('Failed to save comment');
        _showSendError();
        return;
      }

      // Update UI only after successful persistence
      _clearDraftForCollection(collectionID);
      if (mounted) {
        setState(() {
          _sendState = SendButtonState.idle;
          if (_selectedCollectionID == collectionID) {
            _comments.insert(0, result);
            if (_replyingTo?.id == replyingTo?.id) {
              _replyingTo = null;
            }
          }

          // Update comment count in shared collections list
          final index = _sharedCollections.indexWhere(
            (c) => c.collection.id == collectionID,
          );
          if (index != -1) {
            final old = _sharedCollections[index];
            _sharedCollections[index] = CollectionCommentInfo(
              collection: old.collection,
              commentCount: old.commentCount + 1,
              thumbnail: old.thumbnail,
            );
          }
        });
        if (_selectedCollectionID == collectionID) {
          _textController.clear();
        }

        // Scroll to the newly added comment (position 0 in reversed list)
        if (_selectedCollectionID == collectionID &&
            _scrollController.hasClients) {
          unawaited(
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            ),
          );
        }
      }
    } catch (e) {
      _sendLoadingTimer?.cancel();
      _logger.severe('Failed to send comment', e);
      _showSendError();
    }
  }

  void _showSendError() {
    if (!mounted) return;
    setState(() => _sendState = SendButtonState.error);

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _sendState == SendButtonState.error) {
        setState(() => _sendState = SendButtonState.idle);
      }
    });
  }

  void _handleCommentDeleted(String commentId) {
    Bus.instance.fire(CommentDeletedEvent(commentId));
    setState(() {
      _comments.removeWhere((c) => c.id == commentId);

      // Decrement comment count in shared collections list
      final index = _sharedCollections.indexWhere(
        (c) => c.collection.id == _selectedCollectionID,
      );
      if (index != -1) {
        final old = _sharedCollections[index];
        _sharedCollections[index] = CollectionCommentInfo(
          collection: old.collection,
          commentCount: old.commentCount - 1,
          thumbnail: old.thumbnail,
        );
      }
    });
  }

  Collection? get _currentCollection {
    if (_sharedCollections.isEmpty) {
      return null;
    }
    return _sharedCollections
        .firstWhere(
          (c) => c.collection.id == _selectedCollectionID,
          orElse: () => _sharedCollections.first,
        )
        .collection;
  }

  _CommentDraftFileKey get _draftFileKey =>
      (userID: _currentUserID, fileID: widget.fileID);

  bool get _canRestoreDraftCollection => widget.highlightCommentID == null;

  _CommentDraftKey get _draftKey => (
    userID: _currentUserID,
    fileID: widget.fileID,
    collectionID: _selectedCollectionID,
  );

  _CommentDraftKey _draftKeyForCollection(int collectionID) => (
    userID: _currentUserID,
    fileID: widget.fileID,
    collectionID: collectionID,
  );

  void _restoreDraftForSelectedCollection() {
    final draft = _commentDrafts[_draftKey];
    final text = draft?.text ?? '';
    _replyingTo = draft?.replyingTo;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _saveOrClearDraft() {
    if (_textController.text.isEmpty && _replyingTo == null) {
      _removeDraftForCollection(_selectedCollectionID);
      return;
    }
    _lastSelectedDraftCollectionIDs[_draftFileKey] = _selectedCollectionID;
    _commentDrafts[_draftKey] = _CommentDraft(
      text: _textController.text,
      replyingTo: _replyingTo,
    );
  }

  void _clearDraftForCollection(int collectionID) {
    _removeDraftForCollection(collectionID);
  }

  void _removeDraftForCollection(int collectionID) {
    _commentDrafts.remove(_draftKeyForCollection(collectionID));
    if (_lastSelectedDraftCollectionIDs[_draftFileKey] == collectionID) {
      final nextCollectionID = _firstDraftCollectionIDForFile();
      if (nextCollectionID == null) {
        _lastSelectedDraftCollectionIDs.remove(_draftFileKey);
      } else {
        _lastSelectedDraftCollectionIDs[_draftFileKey] = nextCollectionID;
      }
    }
  }

  int? _firstDraftCollectionIDForFile() {
    for (final key in _commentDrafts.keys) {
      if (key.userID == _currentUserID && key.fileID == widget.fileID) {
        return key.collectionID;
      }
    }
    return null;
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    return SingleChildScrollView(
      controller: widget.dragController,
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: _sharedCollections.length > 1
                  ? CollectionSelectorWidget(
                      sharedCollections: _sharedCollections,
                      selectedCollectionID: _selectedCollectionID,
                      onCollectionSelected: _onCollectionSelected,
                    )
                  : Text(
                      l10n.commentsCount(count: _comments.length),
                      style: textTheme.bodyBold,
                    ),
            ),
            IconButtonWidget(
              iconButtonType: IconButtonType.rounded,
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final selectedCollection = _currentCollection;
    final canModerateComments =
        selectedCollection != null &&
        (selectedCollection.isOwner(_currentUserID) ||
            selectedCollection.isAdmin(_currentUserID));

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF0E0E0E)
            : colorScheme.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: _isLoading
                      ? const EnteLoadingWidget()
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.only(
                            top: 24,
                            left: 16,
                            right: 16,
                            bottom: 24,
                          ),
                          itemCount:
                              _comments.length + (_hasMoreComments ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _comments.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: EnteLoadingWidget(),
                              );
                            }
                            final comment = _comments[index];
                            final isHighlighted =
                                comment.id == _highlightedCommentID ||
                                comment.id == _scrollTargetHighlightID;
                            // Use widget.highlightCommentID (not state) to keep key stable after dismiss
                            // Priority: highlightCommentID (deep link) > scrollTargetCommentID (tap)
                            final key =
                                (comment.id == widget.highlightCommentID)
                                ? (_highlightedCommentKey ??= GlobalKey())
                                : (comment.id == _scrollTargetCommentID)
                                ? _scrollTargetKey
                                : ValueKey(comment.id);
                            return CommentBubbleWidget(
                              key: key,
                              comment: comment,
                              user: _getUserForComment(comment),
                              isOwnComment: comment.userID == _currentUserID,
                              canModerateComments: canModerateComments,
                              currentUserID: _currentUserID,
                              collectionID: _selectedCollectionID,
                              isHighlighted: isHighlighted,
                              onFetchParent: comment.isReply
                                  ? () => _getParentComment(
                                      comment.parentCommentID!,
                                    )
                                  : null,
                              onFetchReactions: () =>
                                  _getReactionsForComment(comment.id),
                              onReplyTap: () => _onReplyTap(comment),
                              userResolver: _getUserForComment,
                              onCommentDeleted: () =>
                                  _handleCommentDeleted(comment.id),
                              onAutoHighlightDismissed: () {
                                if (mounted &&
                                    (_highlightedCommentID == comment.id ||
                                        _scrollTargetHighlightID ==
                                            comment.id)) {
                                  setState(() {
                                    if (_highlightedCommentID == comment.id) {
                                      _highlightedCommentID = null;
                                    }
                                    if (_scrollTargetHighlightID ==
                                        comment.id) {
                                      _scrollTargetHighlightID = null;
                                    }
                                  });
                                  // Don't clear _highlightedCommentKey - prevents avatar flicker
                                }
                              },
                              onParentQuoteTap: comment.isReply
                                  ? () => _scrollToParentComment(
                                      comment.parentCommentID!,
                                    )
                                  : null,
                              onAuthorTap: () =>
                                  openSocialActorContactDestination(
                                    context,
                                    _getUserForComment(comment),
                                    currentUserID: _currentUserID,
                                    navigationContext: widget.launchContext,
                                    dismissCurrentRoute: true,
                                  ),
                            );
                          },
                        ),
                ),
              ),
              CommentInputWidget(
                replyingTo: _replyingTo,
                replyingToUser: _replyingTo != null
                    ? _getUserForComment(_replyingTo!)
                    : null,
                currentUserID: _currentUserID,
                onDismissReply: _dismissReply,
                controller: _textController,
                focusNode: _inputFocusNode,
                onSend: _sendComment,
                sendState: _sendState,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
