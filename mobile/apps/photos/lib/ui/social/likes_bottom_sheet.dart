import "dart:async";

import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/social/reaction.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/services/collections_service.dart";
import 'package:photos/services/social_notification_coordinator.dart';
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/social/social_actor_contact_navigation.dart";
import "package:photos/ui/social/widgets/collection_selector_widget.dart";
import "package:photos/ui/social/widgets/resolved_social_user_name.dart";

const _shrinkWrapThreshold = 30;

/// Shows the likes bottom sheet for a file
Future<void> showLikesBottomSheet(
  BuildContext context, {
  required int fileID,
  required int initialCollectionID,
  List<Collection>? sharedCollections,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LikesBottomSheet(
      launchContext: context,
      fileID: fileID,
      initialCollectionID: initialCollectionID,
      sharedCollections: sharedCollections,
    ),
  );
}

class LikesBottomSheet extends StatefulWidget {
  final BuildContext launchContext;
  final int fileID;
  final int initialCollectionID;
  final List<Collection>? sharedCollections;

  const LikesBottomSheet({
    required this.launchContext,
    required this.fileID,
    required this.initialCollectionID,
    this.sharedCollections,
    super.key,
  });

  @override
  State<LikesBottomSheet> createState() => _LikesBottomSheetState();
}

class _LikesBottomSheetState extends State<LikesBottomSheet> {
  static const _maxHeightFraction = 0.7;
  static const _animationDuration = Duration(milliseconds: 200);

  List<Reaction> _likes = [];
  bool _isLoading = true;
  bool _hasError = false;
  List<CollectionLikeInfo> _sharedCollections = [];
  late int _selectedCollectionID;
  late final int _currentUserID;
  Map<String, String> _anonDisplayNames = {};

  @override
  void initState() {
    super.initState();
    unawaited(SocialNotificationCoordinator.instance.markSocialSeen());
    _currentUserID = Configuration.instance.getUserID()!;
    _selectedCollectionID = widget.initialCollectionID;
    _loadSharedCollections();
  }

  bool _isOpenedFromHiddenCollection() => CollectionsService.instance
      .getHiddenCollectionIds()
      .contains(widget.initialCollectionID);

  Future<void> _loadSharedCollections() async {
    try {
      final sharedCollectionsList =
          widget.sharedCollections ??
          await CollectionsService.instance.getSharedCollectionsForFile(
            widget.fileID,
            includeHidden: _isOpenedFromHiddenCollection(),
          );

      // Fetch like counts and thumbnails in parallel
      final sharedCollections = await Future.wait(
        sharedCollectionsList.map((collection) async {
          final likes = await SocialDataProvider.instance
              .getReactionsForFileInCollection(widget.fileID, collection.id);
          final thumbnail = await CollectionsService.instance.getCover(
            collection,
          );
          return CollectionLikeInfo(
            collection: collection,
            likeCount: likes.length,
            thumbnail: thumbnail,
          );
        }),
      );

      if (!mounted) return;

      // If no shared collections, close the sheet
      if (sharedCollections.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      // Validate selected collection is in the shared list
      final isSelectedInShared = sharedCollections.any(
        (info) => info.collection.id == _selectedCollectionID,
      );

      setState(() {
        _sharedCollections = sharedCollections;
        if (!isSelectedInShared) {
          _selectedCollectionID = sharedCollections.first.collection.id;
        }
      });

      unawaited(_loadLikes());
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadLikes() async {
    setState(() => _isLoading = true);

    try {
      // Sync reactions from server before loading locally
      await SocialDataProvider.instance.syncFileReactions(
        _selectedCollectionID,
        widget.fileID,
      );

      final results = await Future.wait([
        SocialDataProvider.instance.getReactionsForFileInCollection(
          widget.fileID,
          _selectedCollectionID,
        ),
        SocialDataProvider.instance.getAnonDisplayNamesForCollection(
          _selectedCollectionID,
        ),
      ]);

      final likes = results[0] as List<Reaction>;
      final anonNames = results[1] as Map<String, String>;

      if (mounted) {
        setState(() {
          _likes = likes;
          _anonDisplayNames = anonNames;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onCollectionSelected(int collectionID) async {
    // Load likes and anon names for new collection first to avoid flash/jump
    final results = await Future.wait([
      SocialDataProvider.instance.getReactionsForFileInCollection(
        widget.fileID,
        collectionID,
      ),
      SocialDataProvider.instance.getAnonDisplayNamesForCollection(
        collectionID,
      ),
    ]);

    final likes = results[0] as List<Reaction>;
    final anonNames = results[1] as Map<String, String>;

    if (mounted) {
      setState(() {
        _selectedCollectionID = collectionID;
        _likes = likes;
        _anonDisplayNames = anonNames;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final mediaQuery = MediaQuery.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * _maxHeightFraction,
      ),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF0E0E0E)
            : colorScheme.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: _animationDuration,
          curve: Curves.fastOutSlowIn,
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LikesHeader(
                sharedCollections: _sharedCollections,
                selectedCollectionID: _selectedCollectionID,
                likesCount: _likes.length,
                onCollectionSelected: _onCollectionSelected,
                onClose: () => Navigator.of(context).pop(),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: EnteLoadingWidget(size: 24),
                )
              else if (_hasError)
                const _ErrorState()
              else if (_likes.isEmpty)
                const _EmptyState()
              else
                Flexible(
                  child: _LikesList(
                    likes: _likes,
                    currentUserID: _currentUserID,
                    selectedCollectionID: _selectedCollectionID,
                    anonDisplayNames: _anonDisplayNames,
                    onUserTap: (user) => openSocialActorContactDestination(
                      context,
                      user,
                      currentUserID: _currentUserID,
                      navigationContext: widget.launchContext,
                      dismissCurrentRoute: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikesHeader extends StatelessWidget {
  final List<CollectionLikeInfo> sharedCollections;
  final int selectedCollectionID;
  final int likesCount;
  final ValueChanged<int> onCollectionSelected;
  final VoidCallback onClose;

  const _LikesHeader({
    required this.sharedCollections,
    required this.selectedCollectionID,
    required this.likesCount,
    required this.onCollectionSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: sharedCollections.length > 1
                ? LikesCollectionSelectorWidget(
                    sharedCollections: sharedCollections,
                    selectedCollectionID: selectedCollectionID,
                    onCollectionSelected: onCollectionSelected,
                  )
                : Text(
                    l10n.likesCount(count: likesCount),
                    style: textTheme.bodyBold,
                  ),
          ),
          IconButtonWidget(
            iconButtonType: IconButtonType.rounded,
            icon: Icons.close_rounded,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Text(
        l10n.noLikesYet,
        style: textTheme.smallMuted,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Text(
        l10n.couldNotLoadLikes,
        style: textTheme.smallMuted,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LikesList extends StatelessWidget {
  final List<Reaction> likes;
  final int currentUserID;
  final int selectedCollectionID;
  final Map<String, String> anonDisplayNames;
  final ValueChanged<User> onUserTap;

  const _LikesList({
    required this.likes,
    required this.currentUserID,
    required this.selectedCollectionID,
    required this.anonDisplayNames,
    required this.onUserTap,
  });

  User _getUserForReaction(Reaction reaction) {
    if (reaction.isAnonymous) {
      final anonID = reaction.anonUserID;
      final displayName = anonID != null
          ? (anonDisplayNames[anonID] ?? anonID)
          : "Anonymous";
      return User(
        id: reaction.userID,
        email: "${anonID ?? "anonymous"}@unknown.com",
        name: displayName,
      );
    }

    return CollectionsService.instance.getFileOwner(
      reaction.userID,
      selectedCollectionID,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListView.builder(
      shrinkWrap: likes.length <= _shrinkWrapThreshold,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: likes.length,
      itemBuilder: (context, index) {
        final reaction = likes[index];
        final user = _getUserForReaction(reaction);
        return _LikeListItem(
          user: user,
          currentUserID: currentUserID,
          youLabel: l10n.you,
          onTap: () => onUserTap(user),
        );
      },
    );
  }
}

class _LikeListItem extends StatelessWidget {
  final User user;
  final int currentUserID;
  final String youLabel;
  final VoidCallback? onTap;

  const _LikeListItem({
    required this.user,
    required this.currentUserID,
    required this.youLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          UserAvatarWidget(
            user,
            currentUserID: currentUserID,
            type: AvatarType.regular,
            addStroke: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: user.id == currentUserID
                ? Text(
                    youLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 20 / 14,
                      letterSpacing: 14 * -0.02,
                      color: colorScheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                : ResolvedSocialUserName(
                    user: user,
                    builder: (context, resolvedName) => Text(
                      resolvedName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 20 / 14,
                        letterSpacing: 14 * -0.02,
                        color: colorScheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          const Icon(EnteIcons.likeFilled, color: Color(0xFF08C225), size: 20),
        ],
      ),
    );

    if (onTap == null || user.id == currentUserID) {
      return row;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
