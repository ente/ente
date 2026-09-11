import "dart:async";
import "dart:math" show max;

import "package:collection/collection.dart";
import "package:dotted_border/dotted_border.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/linalg.dart" as ml;
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/search_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";
import "package:photos/utils/people_sort_util.dart";

class MergePersonSelectionResult {
  final String personId;
  final PersonEntity? person;
  final String? seedClusterId;

  const MergePersonSelectionResult({
    required this.personId,
    this.person,
    this.seedClusterId,
  });
}

Future<MergePersonSelectionResult?> showMergeClustersToPersonPage(
  BuildContext context, {
  List<GenericSearchResult>? initialPersons,
  String? seedClusterId,
}) {
  return routeToPage(
    context,
    MergeClustersToPersonPage(
      initialPersons: initialPersons,
      seedClusterId: seedClusterId,
    ),
  );
}

Future<List<GenericSearchResult>> loadMergeablePersons() async {
  final results = await SearchService.instance.getAllFace(
    null,
    minClusterSize: kMinimumClusterSizeAllFaces,
  );
  return results
      .where(
        (result) =>
            (result.params[kPersonParamID] as String?)?.isNotEmpty ?? false,
      )
      .toList();
}

class MergeClustersToPersonPage extends StatefulWidget {
  final List<GenericSearchResult>? initialPersons;
  final String? seedClusterId;

  const MergeClustersToPersonPage({
    super.key,
    this.initialPersons,
    this.seedClusterId,
  });

  @override
  State<MergeClustersToPersonPage> createState() =>
      _MergeClustersToPersonPageState();
}

class _MergeClustersToPersonPageState extends State<MergeClustersToPersonPage> {
  static final Logger _logger = Logger("MergeClustersToPersonSheet");
  static const _titleActionSize = 36.0;
  static const _searchTitleHeight = 52.0;
  static const _searchTransitionDuration = Duration(milliseconds: 240);

  late Future<List<GenericSearchResult>> _personsFuture;
  String _searchQuery = "";
  bool _isSearchBarVisible = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late PeopleSortKey _sortKey;
  bool _useSimilaritySort = true;
  bool _nameSortAscending = true;
  bool _updatedSortAscending = false;
  bool _photosSortAscending = false;
  Map<String, double> _personToMaxSimilarity = {};

  bool get _showNewPersonTile =>
      widget.seedClusterId != null && widget.seedClusterId!.isNotEmpty;
  bool get _canUseSimilaritySort => _showNewPersonTile;

  @override
  void initState() {
    super.initState();
    final settings = localSettings;
    _sortKey = settings.peopleSortKey();
    _useSimilaritySort =
        settings.peopleSimilaritySortSelected && _canUseSimilaritySort;
    _nameSortAscending = settings.peopleNameSortAscending;
    _updatedSortAscending = settings.peopleUpdatedSortAscending;
    _photosSortAscending = settings.peoplePhotosSortAscending;
    _personsFuture = widget.initialPersons != null
        ? Future.value(widget.initialPersons!)
        : loadMergeablePersons();
    if (_canUseSimilaritySort) {
      _personsFuture = _personsFuture.then((persons) async {
        _personToMaxSimilarity = await _calculateSimilarityWithPersons(persons);
        return persons;
      });
    }
  }

  List<GenericSearchResult> _filterPersons(List<GenericSearchResult> persons) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return persons;
    }
    return persons
        .where((person) => person.name().toLowerCase().contains(query))
        .toList();
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onAddNewPersonSelected() async {
    final seedClusterId = widget.seedClusterId;
    if (seedClusterId == null || seedClusterId.isEmpty) {
      return;
    }
    final result = await routeToPage(context, SaveOrEditPerson(seedClusterId));
    if (!mounted) {
      return;
    }
    if (result is PersonEntity) {
      Navigator.of(context).pop(
        MergePersonSelectionResult(
          personId: result.remoteID,
          person: result,
          seedClusterId: seedClusterId,
        ),
      );
    }
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

  void _sortFaces(List<GenericSearchResult> faces) {
    if (_useSimilaritySort && _canUseSimilaritySort) {
      _sortBySimilarity(faces);
      return;
    }
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
    await localSettings.setPeopleSimilaritySortSelected(_useSimilaritySort);
    if (!_useSimilaritySort) {
      await localSettings.setPeopleSortKey(_sortKey);
      await localSettings.setPeopleNameSortAscending(_nameSortAscending);
      await localSettings.setPeopleUpdatedSortAscending(_updatedSortAscending);
      await localSettings.setPeoplePhotosSortAscending(_photosSortAscending);
      Bus.instance.fire(PeopleSortOrderChangeEvent());
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final smallFontSize = textTheme.small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    final labelHeight = 28 * textScaleFactor;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;

    return Scaffold(
      body: FutureBuilder<List<GenericSearchResult>>(
        future: _personsFuture,
        builder: (context, snapshot) {
          final slivers = <Widget>[];
          if (snapshot.connectionState == ConnectionState.waiting) {
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: EnteLoadingWidget()),
              ),
            );
          } else if (snapshot.hasError) {
            _logger.severe(
              "Failed to load persons for merge",
              snapshot.error,
              snapshot.stackTrace,
            );
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: Icon(Icons.error_outline_rounded)),
              ),
            );
          } else {
            final persons = snapshot.data ?? [];
            final sortedPersons = [...persons];
            _sortFaces(sortedPersons);
            final results = _filterPersons(sortedPersons);
            if (results.isEmpty && !_showNewPersonTile) {
              slivers.add(
                SliverFillRemaining(
                  child: Center(child: Text(context.strings.noResultsFound)),
                ),
              );
            } else {
              final screenWidth = MediaQuery.of(context).size.width;
              final estimatedCount = (screenWidth / 100).floor();
              final crossAxisCount = estimatedCount > 0 ? estimatedCount : 1;
              final itemSize =
                  (screenWidth -
                      ((horizontalEdgePadding * 2) +
                          ((crossAxisCount - 1) * gridPadding))) /
                  crossAxisCount;

              final bottomPadding = MediaQuery.paddingOf(context).bottom;
              slivers.add(
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalEdgePadding,
                    16,
                    horizontalEdgePadding,
                    16 + bottomPadding,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      mainAxisSpacing: gridPadding,
                      crossAxisSpacing: gridPadding,
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: itemSize / (itemSize + labelHeight),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      childCount: results.length + (_showNewPersonTile ? 1 : 0),
                      (context, index) {
                        if (_showNewPersonTile && index == 0) {
                          return _AddNewPersonGridTile(
                            size: itemSize,
                            labelHeight: labelHeight,
                            onTap: _onAddNewPersonSelected,
                          );
                        }
                        final person =
                            results[_showNewPersonTile ? index - 1 : index];
                        final personId =
                            person.params[kPersonParamID] as String?;
                        final personKey =
                            personId != null && personId.isNotEmpty
                            ? personId
                            : person.name();
                        return _ManualPersonGridTile(
                          key: ValueKey(personKey),
                          result: person,
                          size: itemSize,
                          labelHeight: labelHeight,
                          onTap: () => _onPersonSelected(person),
                        );
                      },
                    ),
                  ),
                ),
              );
            }
          }

          return AppBarComponent(
            title: context.strings.addToPerson,
            physics: const BouncingScrollPhysics(),
            titleBuilder: (context, state) => AnimatedSwitcher(
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
                final beginOffset =
                    child.key == const ValueKey("person_search_field")
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
                      key: const ValueKey("person_search_field"),
                      child: TextInputComponent(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: context.strings.search,
                        autofocus: true,
                        shouldUnfocusOnClearOrSubmit: true,
                        prefix: HugeIcon(
                          icon: HugeIcons.strokeRoundedSearch01,
                          size: 18,
                          color: context.componentColors.textLight,
                        ),
                        suffix: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: 18,
                          color: context.componentColors.textLight,
                        ),
                        onSuffixTap: _closeSearch,
                        onChanged: _updateSearchQuery,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey("person_title_row"),
                      child: SizedBox(
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
                              child: IconButtonComponent(
                                variant: IconButtonComponentVariant.primary,
                                shouldSurfaceExecutionStates: false,
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedSearch01,
                                ),
                                onTap: _activateSearch,
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            SizedBox.square(
                              dimension: _titleActionSize,
                              child: galleryAppBarPopupMenuAction<_MergeSortKey>(
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedFilterHorizontal,
                                ),
                                tooltip: context.strings.sort,
                                optionsBuilder: () {
                                  final l10n = context.strings;
                                  final sortKeys = _canUseSimilaritySort
                                      ? _MergeSortKey.values
                                      : _MergeSortKey.values
                                            .where(
                                              (key) =>
                                                  key != _MergeSortKey.similar,
                                            )
                                            .toList();
                                  return sortKeys.map((key) {
                                    String label;
                                    late final String detail;
                                    Widget? activeTrailingWidget;

                                    if (key == _MergeSortKey.similar) {
                                      label = l10n.similar;
                                      detail = l10n.closest;
                                    } else {
                                      final peopleKey =
                                          _peopleSortKeyFromMergeSortKey(key)!;
                                      switch (peopleKey) {
                                        case PeopleSortKey.mostPhotos:
                                          label = l10n.photos;
                                          detail = l10n.count;
                                          break;
                                        case PeopleSortKey.name:
                                          label = l10n.name;
                                          detail = _isSortAscending(peopleKey)
                                              ? l10n.sortAToZ
                                              : l10n.sortZToA;
                                          break;
                                        case PeopleSortKey.lastUpdated:
                                          label = l10n.updated;
                                          detail = _isSortAscending(peopleKey)
                                              ? l10n.sortOldestFirst
                                              : l10n.sortNewestFirst;
                                          break;
                                      }

                                      final isAscending = _isSortAscending(
                                        peopleKey,
                                      );
                                      final directionIcon =
                                          peopleKey == PeopleSortKey.name
                                          ? (isAscending
                                                ? HugeIcons
                                                      .strokeRoundedArrowDown02
                                                : HugeIcons
                                                      .strokeRoundedArrowUp02)
                                          : (isAscending
                                                ? HugeIcons
                                                      .strokeRoundedArrowUp02
                                                : HugeIcons
                                                      .strokeRoundedArrowDown02);
                                      activeTrailingWidget = HugeIcon(
                                        icon: directionIcon,
                                        size: 12,
                                        strokeWidth: 3,
                                        color:
                                            context.componentColors.textLight,
                                      );
                                    }

                                    final isSelected =
                                        _selectedMergeSortKey == key;
                                    return EntePopupMenuOption(
                                      value: key,
                                      label: label,
                                      secondaryLabel: isSelected
                                          ? detail
                                          : null,
                                      isActive: isSelected,
                                      activeTrailingWidget:
                                          activeTrailingWidget,
                                    );
                                  }).toList();
                                },
                                onSelected: _selectSortKey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            titleBuilderHeight: _searchTitleHeight,
            slivers: slivers,
          );
        },
      ),
    );
  }

  void _selectSortKey(_MergeSortKey selectedKey) {
    final currentKey = _selectedMergeSortKey;
    if (selectedKey == currentKey) {
      if (selectedKey == _MergeSortKey.similar ||
          !_canToggleSortDirection(_sortKey)) {
        return;
      }
      setState(() {
        _toggleSortDirection(_sortKey);
      });
      unawaited(_persistSortPreferences());
      return;
    }

    setState(() {
      if (selectedKey == _MergeSortKey.similar) {
        _useSimilaritySort = true;
      } else {
        _useSimilaritySort = false;
        _sortKey = _peopleSortKeyFromMergeSortKey(selectedKey)!;
      }
    });
    unawaited(_persistSortPreferences());
  }

  void _onPersonSelected(GenericSearchResult result) {
    final personId = result.params[kPersonParamID] as String?;
    if (personId == null || personId.isEmpty) {
      return;
    }
    Navigator.of(context).pop(MergePersonSelectionResult(personId: personId));
  }

  _MergeSortKey get _selectedMergeSortKey =>
      _useSimilaritySort && _canUseSimilaritySort
      ? _MergeSortKey.similar
      : _mergeSortKeyFromPeopleSortKey(_sortKey);

  _MergeSortKey _mergeSortKeyFromPeopleSortKey(PeopleSortKey key) {
    switch (key) {
      case PeopleSortKey.mostPhotos:
        return _MergeSortKey.mostPhotos;
      case PeopleSortKey.name:
        return _MergeSortKey.name;
      case PeopleSortKey.lastUpdated:
        return _MergeSortKey.lastUpdated;
    }
  }

  PeopleSortKey? _peopleSortKeyFromMergeSortKey(_MergeSortKey key) {
    switch (key) {
      case _MergeSortKey.similar:
        return null;
      case _MergeSortKey.mostPhotos:
        return PeopleSortKey.mostPhotos;
      case _MergeSortKey.name:
        return PeopleSortKey.name;
      case _MergeSortKey.lastUpdated:
        return PeopleSortKey.lastUpdated;
    }
  }

  void _sortBySimilarity(List<GenericSearchResult> persons) {
    if (_personToMaxSimilarity.isEmpty) {
      return;
    }
    persons.sort((a, b) {
      final personIdA = a.params[kPersonParamID] as String?;
      final personIdB = b.params[kPersonParamID] as String?;
      final similarityA = personIdA != null
          ? _personToMaxSimilarity[personIdA] ?? 0
          : 0;
      final similarityB = personIdB != null
          ? _personToMaxSimilarity[personIdB] ?? 0
          : 0;
      final compareValue = similarityB.compareTo(similarityA);
      if (compareValue != 0) {
        return compareValue;
      }
      return compareAsciiLowerCaseNatural(a.name(), b.name());
    });
  }

  Future<Map<String, double>> _calculateSimilarityWithPersons(
    List<GenericSearchResult> persons,
  ) async {
    final seedClusterId = widget.seedClusterId;
    if (!_canUseSimilaritySort || seedClusterId == null || persons.isEmpty) {
      return {};
    }
    final allClusterSummary = await MLDataDB.instance.getAllClusterSummary();
    final currentClusterEmbeddingData = allClusterSummary[seedClusterId]?.$1;
    if (currentClusterEmbeddingData == null) {
      return {};
    }
    final ml.Vector currentClusterEmbedding = ml.Vector.fromList(
      EVector.fromBuffer(currentClusterEmbeddingData).values,
      dtype: ml.DType.float32,
    );

    final personIds = persons
        .map((result) => result.params[kPersonParamID] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
    if (personIds.isEmpty) {
      return {};
    }

    final clusterToPerson = await MLDataDB.instance.getClusterIDToPersonID();
    clusterToPerson.removeWhere((_, personId) => !personIds.contains(personId));
    allClusterSummary.removeWhere(
      (key, value) => !clusterToPerson.containsKey(key),
    );
    final Map<String, ml.Vector> allClusterEmbeddings = allClusterSummary.map(
      (key, value) => MapEntry(
        key,
        ml.Vector.fromList(
          EVector.fromBuffer(value.$1).values,
          dtype: ml.DType.float32,
        ),
      ),
    );

    for (final entry in allClusterEmbeddings.entries) {
      final personId = clusterToPerson[entry.key]!;
      final similarity = currentClusterEmbedding.dot(entry.value);
      _personToMaxSimilarity[personId] = max(
        _personToMaxSimilarity[personId] ?? double.negativeInfinity,
        similarity,
      );
    }
    return _personToMaxSimilarity;
  }
}

enum _MergeSortKey { similar, mostPhotos, name, lastUpdated }

class _AddNewPersonGridTile extends StatelessWidget {
  final double size;
  final double labelHeight;
  final VoidCallback onTap;

  const _AddNewPersonGridTile({
    required this.size,
    required this.labelHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final textScaler = MediaQuery.textScalerOf(context);
    const strokeWidth = 1.0;
    final innerSize = size - strokeWidth * 2;
    final fontSize = textTheme.small.fontSize ?? 14;
    final lineHeight = textTheme.small.height ?? (17 / 14);
    final textHeight = textScaler.scale(fontSize) * lineHeight;
    final labelTopPadding =
        6 + strokeWidth + ((labelHeight - 6 - textHeight) / 2);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DottedBorder(
            options: CustomPathDottedBorderOptions(
              customPath: faceThumbnailSquircleOuterPath,
              color: colorScheme.strokeMuted,
              strokeWidth: strokeWidth,
              dashPattern: const [4, 4],
              padding: EdgeInsets.zero,
            ),
            child: SizedBox(
              height: innerSize,
              width: innerSize,
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  color: colorScheme.strokeMuted,
                  size: 24,
                ),
              ),
            ),
          ),
          SizedBox(
            height: labelHeight,
            child: Padding(
              padding: EdgeInsets.only(top: labelTopPadding),
              child: Text(
                context.strings.addPerson,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: textTheme.small,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualPersonGridTile extends StatelessWidget {
  final GenericSearchResult result;
  final double size;
  final double labelHeight;
  final VoidCallback onTap;

  const _ManualPersonGridTile({
    super.key,
    required this.result,
    required this.size,
    required this.labelHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = getEnteTextTheme(context).small;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaceThumbnailSquircleClip(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: getEnteColorScheme(context).strokeFaint,
              ),
              child: _FaceSearchResult(result: result),
            ),
          ),
          SizedBox(
            height: labelHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                result.name(),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceSearchResult extends StatelessWidget {
  final GenericSearchResult result;

  const _FaceSearchResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final params = result.params;
    return PersonFaceWidget(
      personId: params[kPersonParamID],
      clusterID: params[kClusterParamId],
      key: params.containsKey(kPersonWidgetKey)
          ? ValueKey(params[kPersonWidgetKey])
          : ValueKey(params[kPersonParamID] ?? params[kClusterParamId]),
    );
  }
}
