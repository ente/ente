import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/search_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/banners/save_faces_banner.dart";
import "package:photos/ui/components/bottom_action_bar/people_bottom_action_bar_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/ui/viewer/people/person_gallery_suggestion.dart";
import "package:photos/ui/viewer/people/pinned_person_badge.dart";
import "package:photos/ui/viewer/search/result/search_result_page.dart";
import "package:photos/ui/viewer/search_tab/people_section.dart";
import "package:photos/utils/people_sort_util.dart";

class PeopleSectionAllPage extends StatefulWidget {
  const PeopleSectionAllPage({super.key, this.startInSearchMode = false});

  final bool startInSearchMode;

  @override
  State<PeopleSectionAllPage> createState() => _PeopleSectionAllPageState();
}

class _PeopleSectionAllPageState extends State<PeopleSectionAllPage> {
  final _selectedPeople = SelectedPeople();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selectedPeople,
      builder: (context, _) {
        final hasSelection = _selectedPeople.personIds.isNotEmpty;

        return Scaffold(
          body: PeopleSectionAllSelectionWrapper(
            selectedPeople: _selectedPeople,
            showSearchBar: true,
            startInSearchMode: widget.startInSearchMode,
            includeEmptyPersons: true,
          ),
          bottomNavigationBar: hasSelection
              ? PeopleBottomActionBarWidget(
                  _selectedPeople,
                  onCancel: () {
                    _selectedPeople.clearAll();
                  },
                )
              : null,
        );
      },
    );
  }
}

class PeopleSectionAllSelectionWrapper extends StatefulWidget {
  final SelectedPeople selectedPeople;
  final bool showSearchBar;
  final bool startInSearchMode;
  final bool includeEmptyPersons;

  const PeopleSectionAllSelectionWrapper({
    super.key,
    required this.selectedPeople,
    this.showSearchBar = false,
    this.startInSearchMode = false,
    this.includeEmptyPersons = false,
  });

  @override
  State<PeopleSectionAllSelectionWrapper> createState() =>
      _PeopleSectionAllSelectionWrapperState();
}

class _PeopleSectionAllSelectionWrapperState
    extends State<PeopleSectionAllSelectionWrapper> {
  @override
  Widget build(BuildContext context) {
    return PeopleSectionAllWidget(
      selectedPeople: widget.selectedPeople,
      showSearchBar: widget.showSearchBar,
      startInSearchMode: widget.startInSearchMode,
      includeEmptyPersons: widget.includeEmptyPersons,
    );
  }
}

class SelectablePersonSearchExample extends StatelessWidget {
  final GenericSearchResult searchResult;
  final double size;
  final SelectedPeople selectedPeople;
  final bool isDefaultFace;

  const SelectablePersonSearchExample({
    super.key,
    required this.searchResult,
    required this.selectedPeople,
    this.size = 102,
    this.isDefaultFace = false,
  });

  void _handleTap(BuildContext context) {
    if (isLocalGalleryMode) {
      _handleNavigation(context);
      return;
    }
    if (selectedPeople.personIds.isNotEmpty) {
      _toggleSelection();
    } else {
      _handleNavigation(context);
    }
  }

  void _handleLongPress() {
    if (isLocalGalleryMode) {
      return;
    }
    _toggleSelection();
  }

  void _toggleSelection() {
    final personId = searchResult.params[kPersonParamID] as String?;
    final clusterId = searchResult.params[kClusterParamId] as String?;

    final idToUse = (personId != null && personId.isNotEmpty)
        ? personId
        : clusterId;

    if (idToUse != null && idToUse.isNotEmpty) {
      selectedPeople.toggleSelection(idToUse);
    }
  }

  void _handleNavigation(BuildContext context) {
    RecentSearches().add(searchResult.name());
    if (searchResult.onResultTap != null) {
      searchResult.onResultTap!(context);
    } else {
      routeToPage(context, SearchResultPage(searchResult));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCluster =
        searchResult.type() == ResultType.faces &&
        searchResult.params.containsKey(kClusterParamId);
    final bool isPinnedPerson =
        !isCluster && (searchResult.params[kPersonPinned] as bool? ?? false);

    return ListenableBuilder(
      listenable: selectedPeople,
      builder: (context, _) {
        final personId = searchResult.params[kPersonParamID] as String?;
        final clusterId = searchResult.params[kClusterParamId] as String?;
        final idToCheck = (personId != null && personId.isNotEmpty)
            ? personId
            : clusterId;
        final bool isSelected = idToCheck != null
            ? selectedPeople.isPersonSelected(idToCheck)
            : false;

        return GestureDetector(
          onTap: () => _handleTap(context),
          onLongPress: _handleLongPress,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  FaceThumbnailSquircleClip(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: getEnteColorScheme(context).strokeFaint,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      late Widget child;

                      if (searchResult.previewThumbnail() != null) {
                        child = searchResult.type() != ResultType.faces
                            ? ThumbnailWidget(
                                searchResult.previewThumbnail()!,
                                shouldShowSyncStatus: false,
                              )
                            : FaceSearchResult(
                                searchResult,
                                displaySize: size - 2,
                                isDefaultFace: isDefaultFace,
                              );
                      } else {
                        child = const NoThumbnailWidget(addBorder: false);
                      }
                      return SizedBox(
                        width: size - 2,
                        height: size - 2,
                        child: FaceThumbnailSquircleClip(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child,
                              if (isSelected)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: isSelected
                          ? const SelectAllStatusIcon(
                              isSelected: true,
                              size: 18,
                              selectedFillColor: Colors.white,
                              selectedTickCutsOut: true,
                            )
                          : null,
                    ),
                  ),
                  if (isPinnedPerson)
                    const Positioned(
                      left: -6,
                      top: -6,
                      child: PinnedPersonBadge(),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 0),
                child: Text(
                  isCluster ? " " : searchResult.name(),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: getEnteTextTheme(context).small,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FaceSearchResult extends StatelessWidget {
  final SearchResult searchResult;
  final double displaySize;
  final bool isDefaultFace;

  const FaceSearchResult(
    this.searchResult, {
    required this.displaySize,
    super.key,
    this.isDefaultFace = false,
  });

  @override
  Widget build(BuildContext context) {
    final params = (searchResult as GenericSearchResult).params;
    final int cachedPixelWidth =
        (displaySize * MediaQuery.devicePixelRatioOf(context)).toInt();
    return PersonFaceWidget(
      personId: params[kPersonParamID],
      clusterID: params[kClusterParamId],
      cachedPixelWidth: cachedPixelWidth,
      key: params.containsKey(kPersonWidgetKey)
          ? ValueKey(params[kPersonWidgetKey])
          : ValueKey(params[kPersonParamID] ?? params[kClusterParamId]),
      keepAlive: isDefaultFace,
    );
  }
}

class PeopleSectionAllWidget extends StatefulWidget {
  const PeopleSectionAllWidget({
    super.key,
    this.selectedPeople,
    this.namedOnly = false,
    this.showSearchBar = false,
    this.startInSearchMode = false,
    this.includeEmptyPersons = false,
  });

  final SelectedPeople? selectedPeople;
  final bool namedOnly;
  final bool showSearchBar;
  final bool startInSearchMode;
  final bool includeEmptyPersons;

  @override
  State<PeopleSectionAllWidget> createState() => _PeopleSectionAllWidgetState();
}

class _PeopleSectionAllWidgetState extends State<PeopleSectionAllWidget> {
  static const _titleActionSize = 36.0;
  static const _searchTitleHeight = 52.0;
  static const _searchTransitionDuration = Duration(milliseconds: 240);

  late Future<List<GenericSearchResult>> sectionData;
  List<GenericSearchResult> normalFaces = [];
  List<GenericSearchResult> extraFaces = [];
  final streamSubscriptions = <StreamSubscription>[];
  bool _showingAllFaces = false;
  bool _showingIgnoredPeople = false;
  bool _isLoaded = false;
  bool _isInitialLoad = true;
  bool userDismissedPersonGallerySuggestion = false;
  String _searchQuery = "";
  late bool _isSearchBarVisible;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int _suggestionReloadToken = 0;
  final Debouncer _peopleReloadDebouncer = Debouncer(
    const Duration(milliseconds: 400),
  );
  late PeopleSortKey _sortKey;
  bool _nameSortAscending = true;
  bool _updatedSortAscending = false;
  bool _photosSortAscending = false;

  static const double _sortMenuItemHeight = 52;
  static const double _sortMenuCornerRadius = 12;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  bool get _showMoreLessOption =>
      !_isSearching &&
      !widget.namedOnly &&
      !_showingIgnoredPeople &&
      extraFaces.isNotEmpty;

  List<GenericSearchResult> _filterFaces(List<GenericSearchResult> faces) {
    if (!_isSearching) {
      return faces;
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return faces;
    }
    return faces.where((face) {
      final personId = face.params[kPersonParamID] as String?;
      if (personId == null || personId.isEmpty) {
        return false;
      }
      return face.name().toLowerCase().contains(query);
    }).toList();
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _toggleIgnoredPeopleView() {
    setState(() {
      _showingIgnoredPeople = !_showingIgnoredPeople;
      _isLoaded = false;
      sectionData = getResults();
    });
  }

  @override
  void initState() {
    super.initState();
    _isSearchBarVisible = widget.showSearchBar && widget.startInSearchMode;
    if (_isSearchBarVisible) {
      _focusSearchField();
    }
    final settings = localSettings;
    _sortKey = settings.peopleSortKey();
    _nameSortAscending = settings.peopleNameSortAscending;
    _updatedSortAscending = settings.peopleUpdatedSortAscending;
    _photosSortAscending = settings.peoplePhotosSortAscending;
    sectionData = getResults(init: true);

    final streamsToListenTo = SectionType.face.viewAllUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          if (event is PeopleChangedEvent &&
              event.type == PeopleEventType.addedClusterToPerson) {
            normalFaces.removeWhere(
              (person) =>
                  (person.params[kClusterParamId] as String?) == event.source,
            );
            extraFaces.removeWhere(
              (person) =>
                  (person.params[kClusterParamId] as String?) == event.source,
            );
            setState(() {
              _suggestionReloadToken++;
            });
          } else if (event is PeopleChangedEvent &&
              event.type == PeopleEventType.syncDone) {
            _peopleReloadDebouncer.run(() async {
              if (!mounted) {
                return;
              }
              setState(() {
                _isInitialLoad = false;
                _isLoaded = false;
                sectionData = getResults();
              });
            });
          } else {
            _peopleReloadDebouncer.run(() async {
              if (!mounted) {
                return;
              }
              setState(() {
                _suggestionReloadToken++;
                _isInitialLoad = false;
                _isLoaded = false;
                sectionData = getResults();
              });
            });
          }
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

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _isSearchBarVisible = false;
      _searchQuery = "";
    });
  }

  Future<List<GenericSearchResult>> getResults({bool init = false}) async {
    final allFaces = await SearchService.instance.getAllFace(
      null,
      minClusterSize: kMinimumClusterSizeAllFaces,
      showIgnoredOnly: _showingIgnoredPeople,
      includeEmptyPersons: widget.includeEmptyPersons,
    );
    normalFaces.clear();
    extraFaces.clear();
    if (_showingIgnoredPeople) {
      normalFaces.addAll(allFaces);
    } else {
      for (final face in allFaces) {
        if (face.fileCount() >= kMinimumClusterSizeSearchResult ||
            face.name().isNotEmpty) {
          normalFaces.add(face);
        } else {
          extraFaces.add(face);
        }
      }
      if (normalFaces.isEmpty && extraFaces.isNotEmpty) {
        normalFaces.addAll(extraFaces);
        extraFaces.clear();
      }
    }
    if (widget.showSearchBar) {
      _sortFaces(normalFaces);
      _sortFaces(extraFaces);
    }
    if (_showingIgnoredPeople) {
      _prioritizeNamedIgnoredPeople(normalFaces);
    }
    final showAllFaces = _showingAllFaces || _showingIgnoredPeople;
    final results = showAllFaces
        ? [...normalFaces, ...extraFaces]
        : normalFaces;

    if (widget.namedOnly) {
      results.removeWhere((element) => element.params[kPersonParamID] == null);

      if (init) {
        // sort widget.selectedPeople first
        results.sort((a, b) {
          final aIndex =
              widget.selectedPeople?.personIds.contains(
                a.params[kPersonParamID],
              ) ??
              false;
          final bIndex =
              widget.selectedPeople?.personIds.contains(
                b.params[kPersonParamID],
              ) ??
              false;
          if (aIndex && !bIndex) return -1;
          if (!aIndex && bIndex) return 1;
          final bool aPinned = a.params[kPersonPinned] as bool? ?? false;
          final bool bPinned = b.params[kPersonPinned] as bool? ?? false;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return a.name().compareTo(b.name());
        });
      }
    }
    _isLoaded = true;
    return results;
  }

  bool _isSortAscending(PeopleSortKey key) {
    switch (key) {
      case PeopleSortKey.name:
        return _nameSortAscending;
      case PeopleSortKey.lastUpdated:
        return _updatedSortAscending;
      case PeopleSortKey.mostPhotos:
        return _photosSortAscending;
    }
  }

  bool _toggleSortDirection(PeopleSortKey key) {
    switch (key) {
      case PeopleSortKey.name:
        _nameSortAscending = !_nameSortAscending;
        return true;
      case PeopleSortKey.lastUpdated:
        _updatedSortAscending = !_updatedSortAscending;
        return true;
      case PeopleSortKey.mostPhotos:
        _photosSortAscending = !_photosSortAscending;
        return true;
    }
  }

  bool _canToggleSortDirection(PeopleSortKey key) {
    return key == PeopleSortKey.name ||
        key == PeopleSortKey.lastUpdated ||
        key == PeopleSortKey.mostPhotos;
  }

  bool _isUnnamedIgnoredDisplayName(String name) {
    final normalizedName = name.trim().toLowerCase();
    return normalizedName.isEmpty ||
        normalizedName == "(hidden)" ||
        normalizedName == "(ignored)";
  }

  void _prioritizeNamedIgnoredPeople(List<GenericSearchResult> faces) {
    if (faces.length < 2) {
      return;
    }

    final namedIgnoredPeople = <GenericSearchResult>[];
    final unnamedIgnoredPeople = <GenericSearchResult>[];

    for (final face in faces) {
      if (_isUnnamedIgnoredDisplayName(face.name())) {
        unnamedIgnoredPeople.add(face);
      } else {
        namedIgnoredPeople.add(face);
      }
    }

    faces
      ..clear()
      ..addAll(namedIgnoredPeople)
      ..addAll(unnamedIgnoredPeople);
  }

  void _sortFaces(List<GenericSearchResult> faces) {
    sortPeopleFaces(
      faces,
      PeopleSortConfig(
        sortKey: _sortKey,
        nameSortAscending: _nameSortAscending,
        updatedSortAscending: _updatedSortAscending,
        photosSortAscending: _photosSortAscending,
      ),
    );
  }

  Future<void> _persistSortPreferences() async {
    await localSettings.setPeopleSortKey(_sortKey);
    await localSettings.setPeopleNameSortAscending(_nameSortAscending);
    await localSettings.setPeopleUpdatedSortAscending(_updatedSortAscending);
    await localSettings.setPeoplePhotosSortAscending(_photosSortAscending);
    Bus.instance.fire(PeopleSortOrderChangeEvent());
  }

  @override
  void dispose() {
    _peopleReloadDebouncer.cancelDebounceTimer();
    for (var subscriptions in streamSubscriptions) {
      subscriptions.cancel();
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final smallFontSize = textTheme.small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;
    const labelHeight = 28.0;

    return FutureBuilder<List<GenericSearchResult>>(
      future: sectionData,
      builder: (context, snapshot) {
        final slivers = <Widget>[];
        if (!_isLoaded &&
            snapshot.connectionState == ConnectionState.waiting &&
            _isInitialLoad) {
          slivers.add(
            const SliverFillRemaining(
              child: Center(child: EnteLoadingWidget()),
            ),
          );
          return _buildScrollBody(slivers, textTheme, colorScheme);
        } else if (snapshot.hasError) {
          slivers.add(
            const SliverFillRemaining(
              child: Center(child: Icon(Icons.error_outline_rounded)),
            ),
          );
          return _buildScrollBody(slivers, textTheme, colorScheme);
        } else {
          final filteredNormalFaces = _filterFaces(normalFaces);
          final filteredExtraFaces = _filterFaces(extraFaces);
          final hasResults = _isSearching
              ? filteredNormalFaces.isNotEmpty || filteredExtraFaces.isNotEmpty
              : filteredNormalFaces.isNotEmpty ||
                    (!widget.namedOnly && filteredExtraFaces.isNotEmpty);
          if (_isLoaded && !hasResults) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsFound + '.',
                  ),
                ),
              ),
            );
            return _buildScrollBody(slivers, textTheme, colorScheme);
          }
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = (screenWidth / 100).floor();

          final itemSize =
              (screenWidth -
                  ((horizontalEdgePadding * 2) +
                      ((crossAxisCount - 1) * gridPadding))) /
              crossAxisCount;
          final gridItemHeight = itemSize + (labelHeight * textScaleFactor);

          if (_isSearching) {
            final searchResults = [
              ...filteredNormalFaces,
              ...filteredExtraFaces,
            ];
            final defaultFaces = filteredNormalFaces.toSet();
            slivers.add(
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalEdgePadding,
                  16,
                  horizontalEdgePadding,
                  16,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisSpacing: gridPadding,
                    crossAxisSpacing: gridPadding,
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: itemSize / gridItemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: searchResults.length,
                    (context, index) {
                      final result = searchResults[index];
                      return !widget.namedOnly
                          ? SelectablePersonSearchExample(
                              searchResult: result,
                              size: itemSize,
                              selectedPeople: widget.selectedPeople!,
                              isDefaultFace: defaultFaces.contains(result),
                            )
                          : PersonSearchExample(
                              searchResult: result,
                              size: itemSize,
                              selectedPeople: widget.selectedPeople!,
                            );
                    },
                  ),
                ),
              ),
            );
            slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
          } else {
            final showAllFaces = _showingAllFaces || _showingIgnoredPeople;
            final showExtraFaces =
                showAllFaces && filteredExtraFaces.isNotEmpty;
            slivers.addAll([
              if (isLocalGalleryMode &&
                  !Configuration.instance.hasConfiguredAccount())
                const SliverToBoxAdapter(child: SaveFacesBanner()),
              (!userDismissedPersonGallerySuggestion &&
                      !widget.namedOnly &&
                      !_showingIgnoredPeople)
                  ? SliverToBoxAdapter(
                      child: Dismissible(
                        key: const Key("personGallerySuggestionAll"),
                        direction: DismissDirection.horizontal,
                        onDismissed: (direction) {
                          setState(() {
                            userDismissedPersonGallerySuggestion = true;
                          });
                        },
                        child: PersonGallerySuggestion(
                          key: ValueKey(
                            'personGallerySuggestionAll_$_suggestionReloadToken',
                          ),
                          person: null,
                          onClose: () {
                            setState(() {
                              userDismissedPersonGallerySuggestion = true;
                            });
                          },
                        ),
                      ),
                    )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalEdgePadding,
                  16,
                  horizontalEdgePadding,
                  16,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisSpacing: gridPadding,
                    crossAxisSpacing: gridPadding,
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: itemSize / gridItemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: filteredNormalFaces.length,
                    (context, index) {
                      return !widget.namedOnly
                          ? SelectablePersonSearchExample(
                              searchResult: filteredNormalFaces[index],
                              size: itemSize,
                              selectedPeople: widget.selectedPeople!,
                              isDefaultFace: true,
                            )
                          : PersonSearchExample(
                              searchResult: filteredNormalFaces[index],
                              size: itemSize,
                              selectedPeople: widget.selectedPeople!,
                            );
                    },
                  ),
                ),
              ),
              if (_showMoreLessOption)
                SliverToBoxAdapter(child: _buildShowMoreOrLessButton(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (showExtraFaces)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    horizontalEdgePadding,
                    16,
                    horizontalEdgePadding,
                    16,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      mainAxisSpacing: gridPadding,
                      crossAxisSpacing: gridPadding,
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: itemSize / gridItemHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      childCount: filteredExtraFaces.length,
                      (context, index) {
                        return !widget.namedOnly
                            ? SelectablePersonSearchExample(
                                searchResult: filteredExtraFaces[index],
                                size: itemSize,
                                selectedPeople: widget.selectedPeople!,
                                isDefaultFace: false,
                              )
                            : PersonSearchExample(
                                searchResult: filteredExtraFaces[index],
                                size: itemSize,
                                selectedPeople: widget.selectedPeople!,
                              );
                      },
                    ),
                  ),
                ),
              if (showExtraFaces)
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ]);
          }
          return _buildScrollBody(slivers, textTheme, colorScheme);
        }
      },
    );
  }

  Widget _buildScrollBody(
    List<Widget> slivers,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
  ) {
    if (!widget.showSearchBar) {
      return CustomScrollView(slivers: slivers);
    }

    return AppBarComponent(
      title: SectionType.face.sectionTitle(context),
      physics: const BouncingScrollPhysics(),
      titleBuilder: (context, state) =>
          _buildTitle(context, state, textTheme, colorScheme),
      titleBuilderHeight: _searchTitleHeight,
      slivers: slivers,
    );
  }

  Widget _buildTitle(
    BuildContext context,
    HeaderAppBarTitleState state,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
  ) {
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
        final beginOffset = child.key == const ValueKey("people_search_field")
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
              key: const ValueKey("people_search_field"),
              child: _buildSearchField(context),
            )
          : KeyedSubtree(
              key: const ValueKey("people_title_row"),
              child: _buildTitleRow(state, textTheme, colorScheme),
            ),
    );
  }

  Widget _buildTitleRow(
    HeaderAppBarTitleState state,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
  ) {
    return SizedBox(
      height: state.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              state.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: state.textStyle,
            ),
          ),
          const SizedBox(width: Spacing.md),
          SizedBox.square(
            dimension: _titleActionSize,
            child: _buildSearchAction(),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox.square(
            dimension: _titleActionSize,
            child: _buildSortMenu(context, textTheme, colorScheme),
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

  Widget _buildSortMenu(
    BuildContext context,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
  ) {
    return IconButtonComponent(
      variant: IconButtonComponentVariant.primary,
      shouldSurfaceExecutionStates: false,
      icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal),
      onTapDown: (details) async {
        final l10n = AppLocalizations.of(context);
        const sortKeys = PeopleSortKey.values;
        final PeopleSortKey? selectedKey = await showMenu<PeopleSortKey>(
          color: colorScheme.backgroundElevated,
          context: context,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(width: 0.5, color: colorScheme.strokeFaint),
            borderRadius: BorderRadius.circular(_sortMenuCornerRadius),
          ),
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy + 50,
          ),
          items: [
            ...List.generate(sortKeys.length, (index) {
              final key = sortKeys[index];
              return _buildSortMenuItem(
                key,
                index == sortKeys.length - 1,
                textTheme,
                colorScheme,
                l10n,
              );
            }),
            _buildIgnoredPeopleMenuItem(context, textTheme, colorScheme, l10n),
          ],
        );
        if (!mounted || selectedKey == null) {
          return;
        }
        if (selectedKey == _sortKey && !_canToggleSortDirection(selectedKey)) {
          return;
        }
        setState(() {
          if (selectedKey == _sortKey) {
            _toggleSortDirection(selectedKey);
          } else {
            _sortKey = selectedKey;
          }
          _sortFaces(normalFaces);
          _sortFaces(extraFaces);
          if (_showingIgnoredPeople) {
            _prioritizeNamedIgnoredPeople(normalFaces);
          }
        });
        unawaited(_persistSortPreferences());
      },
    );
  }

  PopupMenuItem<PeopleSortKey> _buildSortMenuItem(
    PeopleSortKey key,
    bool isLast,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    String label;
    switch (key) {
      case PeopleSortKey.mostPhotos:
        label = l10n.photos;
        break;
      case PeopleSortKey.name:
        label = l10n.name;
        break;
      case PeopleSortKey.lastUpdated:
        label = l10n.updated;
        break;
    }

    String detail;
    switch (key) {
      case PeopleSortKey.mostPhotos:
        detail = l10n.count;
        break;
      case PeopleSortKey.name:
        detail = _isSortAscending(key) ? l10n.sortAToZ : l10n.sortZToA;
        break;
      case PeopleSortKey.lastUpdated:
        detail = _isSortAscending(key)
            ? l10n.sortOldestFirst
            : l10n.sortNewestFirst;
        break;
    }

    final bool isSelected = _sortKey == key;
    final bool isAscending = _isSortAscending(key);
    final IconData directionIcon = key == PeopleSortKey.name
        ? (isAscending ? Icons.arrow_downward : Icons.arrow_upward)
        : (isAscending ? Icons.arrow_upward : Icons.arrow_downward);

    return PopupMenuItem<PeopleSortKey>(
      value: key,
      padding: EdgeInsets.zero,
      height: _sortMenuItemHeight,
      child: Container(
        width: double.infinity,
        height: _sortMenuItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    width: 0.5,
                    color: colorScheme.strokeFaint,
                  ),
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(label, style: textTheme.mini),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.textMuted.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(detail, style: textTheme.miniMuted),
              const SizedBox(width: 4),
              Icon(directionIcon, size: 16, color: colorScheme.textMuted),
            ],
          ],
        ),
      ),
    );
  }

  PopupMenuItem<PeopleSortKey> _buildIgnoredPeopleMenuItem(
    BuildContext context,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return PopupMenuItem<PeopleSortKey>(
      value: null,
      onTap: _toggleIgnoredPeopleView,
      padding: EdgeInsets.zero,
      height: _sortMenuItemHeight,
      child: Container(
        width: double.infinity,
        height: _sortMenuItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(width: 0.5, color: colorScheme.strokeFaint),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.showIgnored, style: textTheme.miniMuted),
            IgnorePointer(
              child: CupertinoSwitch(
                value: _showingIgnoredPeople,
                onChanged: (_) {},
                activeTrackColor: colorScheme.primary500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowMoreOrLessButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () {
            if (_showingAllFaces) {
              setState(() {
                _showingAllFaces = false;
              });
            } else {
              setState(() {
                _showingAllFaces = true;
              });
            }
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _showingAllFaces
                    ? AppLocalizations.of(context).showLessFaces
                    : AppLocalizations.of(context).showMoreFaces,
                style: getEnteTextTheme(
                  context,
                ).small.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Icon(
                _showingAllFaces
                    ? Icons.keyboard_double_arrow_up_outlined
                    : Icons.keyboard_double_arrow_down_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
