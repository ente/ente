import "package:ente_icons/ente_icons.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/social/social_data_provider.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

final _logger = Logger("LikeCollectionSelectorSheet");

const _greenHeartColor = Color(0xFF08C225);

/// Holds collection info with mutable like state for the selector
class _CollectionLikeState {
  final Collection collection;
  bool isLiked;

  _CollectionLikeState({required this.collection, required this.isLiked});
}

/// Shows the like collection selector bottom sheet
///
/// Parameters:
/// - [fileID]: The uploaded file ID to like
/// - [currentUserID]: Current user's ID for checking existing likes
/// - [collections]: Shared collections eligible for this action
/// - [file]: The EnteFile for displaying thumbnail (optional, will fetch if null)
Future<void> showLikeCollectionSelectorSheet(
  BuildContext context, {
  required int fileID,
  required int currentUserID,
  required List<Collection> collections,
  EnteFile? file,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LikeCollectionSelectorSheet(
      fileID: fileID,
      currentUserID: currentUserID,
      collections: collections,
      file: file,
    ),
  );
}

class LikeCollectionSelectorSheet extends StatefulWidget {
  final int fileID;
  final int currentUserID;
  final List<Collection> collections;
  final EnteFile? file;

  const LikeCollectionSelectorSheet({
    required this.fileID,
    required this.currentUserID,
    required this.collections,
    this.file,
    super.key,
  });

  @override
  State<LikeCollectionSelectorSheet> createState() =>
      _LikeCollectionSelectorSheetState();
}

class _LikeCollectionSelectorSheetState
    extends State<LikeCollectionSelectorSheet> {
  static const _maxHeightFraction = 0.7;

  List<_CollectionLikeState> _collections = [];
  EnteFile? _file;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Load file if not provided (for thumbnail)
      _file ??= await FilesDB.instance.getAnyUploadedFile(widget.fileID);

      // Fetch like states in parallel
      final collectionStates = await Future.wait(
        widget.collections.map((collection) async {
          final reactions = await SocialDataProvider.instance
              .getReactionsForFileInCollection(widget.fileID, collection.id);
          final isLiked = reactions.any(
            (r) => r.userID == widget.currentUserID && !r.isDeleted,
          );
          return _CollectionLikeState(collection: collection, isLiked: isLiked);
        }),
      );

      if (!mounted) return;

      setState(() {
        _collections = collectionStates;
        _isLoading = false;
      });
    } catch (e, s) {
      _logger.severe("Error loading like selector data", e, s);
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleLike(_CollectionLikeState state) async {
    final previousState = state.isLiked;
    // Optimistic UI update
    setState(() => state.isLiked = !state.isLiked);

    try {
      await SocialDataProvider.instance.toggleReaction(
        userID: widget.currentUserID,
        collectionID: state.collection.id,
        fileID: widget.fileID,
      );
    } catch (e) {
      _logger.severe("Failed to toggle like", e);
      if (mounted) {
        setState(() => state.isLiked = previousState);
        if (flagService.internalUser || kDebugMode) {
          showShortToast(
            context,
            AppLocalizations.of(context).failedToUpdateLike,
          );
        }
      }
    }
  }

  Future<void> _likeAll() async {
    // Get collections that aren't already liked
    final toLike = _collections.where((c) => !c.isLiked).toList();

    if (toLike.isEmpty) {
      // All already liked, just close
      Navigator.of(context).pop();
      return;
    }

    // Optimistic UI update
    setState(() {
      for (final c in toLike) {
        c.isLiked = true;
      }
    });

    // Track failures for rollback
    final failed = <_CollectionLikeState>[];

    // Perform all likes in parallel
    await Future.wait(
      toLike.map((c) async {
        try {
          await SocialDataProvider.instance.toggleReaction(
            userID: widget.currentUserID,
            collectionID: c.collection.id,
            fileID: widget.fileID,
          );
        } catch (e) {
          failed.add(c);
          _logger.severe("Failed to like ${c.collection.displayName}", e);
        }
      }),
    );

    if (!mounted) return;

    // Rollback failed items and show toast
    if (failed.isNotEmpty) {
      setState(() {
        for (final c in failed) {
          c.isLiked = false;
        }
      });
      showShortToast(
        context,
        AppLocalizations.of(context).failedToLikeAlbums(count: failed.length),
      );
      // Don't close sheet - let user retry
      return;
    }

    // Close sheet after successful "Like all"
    Navigator.of(context).pop();
  }

  bool get _isVideo => _file?.isVideo ?? false;

  bool get _allLiked => _collections.every((c) => c.isLiked);

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
            : colorScheme.backgroundColour,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button - inlined for simplicity
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButtonWidget(
                    iconButtonType: IconButtonType.rounded,
                    icon: Icons.close_rounded,
                    size: 20,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: EnteLoadingWidget(size: 24),
              )
            else if (_hasError)
              _buildErrorState()
            else ...[
              _FileThumbnail(
                file: _file,
                placeholderColor: colorScheme.fillMuted,
              ),
              _TitleSection(isVideo: _isVideo),
              _buildAlbumsContainer(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsContainer() {
    return Flexible(
      child: Container(
        margin: const EdgeInsets.fromLTRB(21, 16, 21, 16),
        decoration: BoxDecoration(
          color: const Color(0x1FA2A2A2),
          borderRadius: BorderRadius.circular(27),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AlbumsHeader(
              albumCount: _collections.length,
              allLiked: _allLiked,
              onLikeAll: _likeAll,
            ),
            // Album list
            Flexible(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  shrinkWrap: _collections.length <= 10,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _collections.length,
                  itemBuilder: (context, index) {
                    final state = _collections[index];
                    return _AlbumListItem(
                      key: ValueKey(state.collection.id),
                      state: state,
                      onTap: () => _toggleLike(state),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Text(
        l10n.couldNotLoadAlbums,
        style: textTheme.smallMuted,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _AlbumsHeader extends StatelessWidget {
  final int albumCount;
  final bool allLiked;
  final VoidCallback onLikeAll;

  const _AlbumsHeader({
    required this.albumCount,
    required this.allLiked,
    required this.onLikeAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 26, 12, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.albumsCount(count: albumCount), style: textTheme.small),
          GestureDetector(
            onTap: onLikeAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0E0E0E)
                    : colorScheme.backgroundColour,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.likeAll, style: textTheme.small),
                  const SizedBox(width: 10),
                  Icon(
                    allLiked ? EnteIcons.likeFilled : EnteIcons.likeStroke,
                    color: allLiked ? _greenHeartColor : colorScheme.textBase,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleSection extends StatelessWidget {
  final bool isVideo;

  const _TitleSection({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

    final subtitle = isVideo
        ? l10n.selectAlbumToLikeVideo
        : l10n.selectAlbumToLikePhoto;

    return Padding(
      padding: const EdgeInsets.only(top: 27, bottom: 9),
      child: Column(
        children: [
          Text(l10n.like, style: textTheme.h3Bold),
          const SizedBox(height: 9),
          Text(
            subtitle,
            style: textTheme.small.copyWith(color: colorScheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FileThumbnail extends StatelessWidget {
  final EnteFile? file;
  final Color placeholderColor;

  const _FileThumbnail({required this.file, required this.placeholderColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 13, left: 13, right: 13),
            child: SizedBox(
              width: 128,
              height: 128,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: file != null
                    ? ThumbnailWidget(
                        file!,
                        thumbnailSize: thumbnailLargeSize,
                        rawThumbnail: true,
                      )
                    : Container(color: placeholderColor),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Image.asset("assets/select_album_to_like_asset.png"),
          ),
        ],
      ),
    );
  }
}

class _AlbumListItem extends StatelessWidget {
  final _CollectionLikeState state;
  final VoidCallback onTap;

  const _AlbumListItem({required this.state, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final heartContainerBg = isDarkTheme
        ? const Color(0x1A08C225) // ~10% opacity for dark
        : const Color(0x0F08C225); // ~6% opacity for light

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        decoration: BoxDecoration(
          color: isDarkTheme
              ? const Color(0xFF0E0E0E)
              : colorScheme.backgroundColour,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.collection.displayName,
                style: textTheme.small,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: heartContainerBg,
                borderRadius: BorderRadius.circular(9.6),
              ),
              child: Center(
                child: Icon(
                  state.isLiked ? EnteIcons.likeFilled : EnteIcons.likeStroke,
                  color: _greenHeartColor,
                  size: 19.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
