import "dart:async";
import "dart:math" as math;

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/events/event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/hierarchical/magic_filter.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/search/result/magic_result_screen.dart";
import "package:photos/ui/viewer/search/result/searchable_item.dart";

class SearchSectionAllPage extends StatefulWidget {
  final SectionType sectionType;
  final bool startInSearchMode;
  const SearchSectionAllPage({
    required this.sectionType,
    this.startInSearchMode = false,
    super.key,
  });

  @override
  State<SearchSectionAllPage> createState() => _SearchSectionAllPageState();
}

class _SearchSectionAllPageState extends State<SearchSectionAllPage> {
  static const _titleActionSize = 36.0;
  static const _searchTitleHeight = 52.0;
  static const _searchTransitionDuration = Duration(milliseconds: 240);

  late Future<List<SearchResult>> sectionData;
  final streamSubscriptions = <StreamSubscription>[];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = "";
  late bool _isSearchBarVisible;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isSearchBarVisible = widget.startInSearchMode;
    sectionData = widget.sectionType.getData(context);
    if (_isSearchBarVisible) {
      _focusSearchField();
    }

    final streamsToListenTo = widget.sectionType.viewAllUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          setState(() {
            sectionData = widget.sectionType.getData(context);
          });
        }),
      );
    }
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _activateSearch() {
    setState(() {
      _isSearchBarVisible = true;
    });
    _focusSearchField();
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _isSearchBarVisible = false;
      _searchQuery = "";
    });
  }

  List<SearchResult> _filterResults(List<SearchResult> sectionResults) {
    if (!_isSearching) {
      return sectionResults;
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return sectionResults;
    }
    return sectionResults
        .where((result) => result.name().toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    for (var subscriptions in streamSubscriptions) {
      subscriptions.cancel();
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const horizontalEdgePadding = 16.0;
    const minimumBottomClearance = 72.0;
    final cacheExtent = widget.sectionType == SectionType.album ? 400.0 : null;
    final bottomContentPadding = math.max(
      20 + MediaQuery.viewPaddingOf(context).bottom,
      minimumBottomClearance,
    );
    return Scaffold(
      body: FutureBuilder<List<SearchResult>>(
        future: sectionData,
        builder: (context, snapshot) {
          final slivers = <Widget>[];

          if (!snapshot.hasData) {
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: EnteLoadingWidget()),
              ),
            );
            return _buildScaffoldBody(slivers, cacheExtent);
          }

          List<SearchResult> sectionResults = snapshot.data!;

          if (widget.sectionType.sortByName) {
            sectionResults.sort(
              (a, b) => compareAsciiLowerCaseNatural(a.name(), b.name()),
            );
          }

          if (widget.sectionType == SectionType.location) {
            final result = sectionResults.splitMatch(
              (e) => e.type() == ResultType.location,
            );
            sectionResults = result.matched;
            sectionResults.addAll(result.unmatched);
          }

          final filteredResults = _filterResults(sectionResults);
          if (_isSearching && filteredResults.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsFound + '.',
                  ),
                ),
              ),
            );
            return _buildScaffoldBody(slivers, cacheExtent);
          }

          final showCTA = widget.sectionType.isCTAVisible && !_isSearching;
          final totalItems = filteredResults.length + (showCTA ? 1 : 0);
          if (totalItems > 0) {
            slivers.add(
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalEdgePadding,
                  20,
                  horizontalEdgePadding,
                  bottomContentPadding,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index.isOdd) {
                      return const SizedBox(
                        height: ThumbnailListItem.defaultItemSpacing,
                      );
                    }
                    final itemIndex = index ~/ 2;
                    if (showCTA && itemIndex == 0) {
                      return SearchableItemPlaceholder(widget.sectionType);
                    }
                    final adjustedIndex = showCTA ? itemIndex - 1 : itemIndex;
                    final result = filteredResults[adjustedIndex];
                    if (result is AlbumSearchResult) {
                      return SearchableItemWidget(
                        result,
                        resultCount: CollectionsService.instance.getFileCount(
                          result.collectionWithThumbnail.collection,
                        ),
                        onResultTap: () {
                          RecentSearches().add(result.name());
                          routeToPage(
                            context,
                            CollectionPage(
                              result.collectionWithThumbnail,
                              tagPrefix: "searchable_item" + result.heroTag(),
                            ),
                          );
                        },
                      );
                    }

                    if (widget.sectionType == SectionType.magic &&
                        result is GenericSearchResult) {
                      return SearchableItemWidget(
                        result,
                        onResultTap: () {
                          RecentSearches().add(result.name());
                          routeToPage(
                            context,
                            MagicResultScreen(
                              result.resultFiles(),
                              name: result.name(),
                              enableGrouping:
                                  result.params["enableGrouping"]! as bool,
                              fileIdToPosMap:
                                  result.params["fileIdToPosMap"]
                                      as Map<int, int>,
                              heroTag: "searchable_item" + result.heroTag(),
                              magicFilter:
                                  result.getHierarchicalSearchFilter()
                                      as MagicFilter,
                            ),
                          );
                        },
                      );
                    } else if (result is GenericSearchResult) {
                      return SearchableItemWidget(
                        result,
                        onResultTap: result.onResultTap != null
                            ? () => result.onResultTap!(context)
                            : null,
                      );
                    }
                    return SearchableItemWidget(result);
                  }, childCount: totalItems * 2 - 1),
                ),
              ),
            );
          }
          return _buildScaffoldBody(slivers, cacheExtent);
        },
      ),
    );
  }

  Widget _buildScaffoldBody(List<Widget> slivers, double? cacheExtent) {
    return AppBarComponent(
      title: widget.sectionType.sectionTitle(context),
      physics: const BouncingScrollPhysics(),
      cacheExtent: cacheExtent,
      titleBuilder: _buildTitle,
      titleBuilderHeight: _searchTitleHeight,
      slivers: slivers,
    );
  }

  Widget _buildTitle(BuildContext context, HeaderAppBarTitleState state) {
    return AnimatedSwitcher(
      duration: _searchTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final beginOffset = child.key == const ValueKey("search_field")
            ? const Offset(0.035, 0)
            : const Offset(-0.035, 0);
        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
      child: _isSearchBarVisible
          ? KeyedSubtree(
              key: const ValueKey("search_field"),
              child: _buildSearchField(context),
            )
          : KeyedSubtree(
              key: const ValueKey("title_row"),
              child: _buildTitleRow(state),
            ),
    );
  }

  Widget _buildTitleRow(HeaderAppBarTitleState state) {
    return SizedBox(
      height: state.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TooltipComponent(
                message: state.title,
                child: Text(
                  state.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: state.textStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          SizedBox.square(
            dimension: _titleActionSize,
            child: _buildSearchAction(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAction() {
    return IconButtonComponent(
      variant: IconButtonComponentVariant.primary,
      shouldSurfaceExecutionStates: false,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01),
      onTap: _activateSearch,
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.componentColors;
    return TextInputComponent(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: AppLocalizations.of(context).search,
      autofocus: true,
      shouldUnfocusOnClearOrSubmit: true,
      prefix: HugeIcon(
        icon: HugeIcons.strokeRoundedSearch01,
        size: 18,
        color: colors.textLight,
      ),
      suffix: HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: 18,
        color: colors.textLight,
      ),
      onSuffixTap: _closeSearch,
      onChanged: _updateSearchQuery,
    );
  }
}
